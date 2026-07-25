"""
classify.py — Phase 2 classifier for the Bastak Market Intelligence System.

What it does
------------
1. Reads unclassified rows from intel.db (items where classified = 0).
2. For each item, calls the LOCAL Claude CLI as a subprocess (NOT the paid
   API) to score how likely the item is a real SALES LEAD for Bastak
   Instruments: someone building, expanding, or tendering for a flour mill /
   grain milling / food-processing plant that would need lab QC instruments.
3. Parses the CLI's response (a small JSON object) and writes score,
   is_relevant, company, project_type, ai_country, and ai_summary back to
   that row. Commits after EVERY item so an interrupted run keeps whatever
   it already scored.
4. Fails loudly: a CLI error, empty output, or an unparseable response is
   printed as a clear per-item error and counted as a failure. If nothing
   gets classified, or any item fails, the process exits non-zero — it never
   silently exits 0 having scored nothing.

Usage
-----
    python classify.py                       # classify newest 50 unclassified items with haiku
    python classify.py --limit 20
    python classify.py --model sonnet
"""

import argparse
import json
import re
import shutil
import sqlite3
import subprocess
import sys

from init_db import DB_PATH, ensure_schema, ensure_columns

# Make Windows' cp1252 console safe for any stray non-ASCII text (e.g. in
# scraped titles/summaries) instead of crashing with UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

CLI_TIMEOUT_SECONDS = 120
SUMMARY_CHAR_LIMIT = 1500  # keep the prompt (and the OS command line) bounded

PROMPT_TEMPLATE = """You are classifying a news/tender item for Bastak Instruments, a manufacturer of grain, flour, and food-quality analysis LABORATORY equipment. Rate how likely this item represents a real SALES LEAD: someone building, expanding, or tendering for a FLOUR MILL, GRAIN MILLING, or FOOD-PROCESSING plant that would need lab quality-control instruments.

Scoring guide:
8-10 = a confirmed flour-mill / milling-plant PROJECT, TENDER, or EXPANSION, especially with a named company, location, capacity, or budget (a confirmed budget is the highest-intent signal).
4-7 = plausibly relevant but vague (no confirmed project details).
0-3 = generic grain/wheat/commodity price, policy, or unrelated news. Reject these.

Item:
Title: {title}
Source: {source}
Published: {published}
Summary: {summary}

Respond with ONLY a single-line JSON object, no markdown, no explanation outside the JSON:
{{"score": <integer 0-10>, "is_relevant": <true|false>, "company": "<company name or empty string>", "country": "<project country or empty string>", "project_type": "<short label, e.g. 'new mill', 'expansion', 'tender', 'none'>", "summary": "<one sentence on why this is or isn't a lead>"}}
"""

_JSON_OBJECT_RE = re.compile(r"\{.*\}", re.DOTALL)
_FALLBACK_SCORE_RE = re.compile(r"(?<!\d)(10|[0-9])(?!\d)")


def find_claude_cli() -> str:
    path = shutil.which("claude")
    if not path:
        sys.exit(
            "ERROR: the 'claude' CLI was not found on PATH.\n"
            "Install Claude Code and make sure 'claude' is callable from this shell."
        )
    return path


def fetch_unclassified(conn, limit: int):
    sql = (
        "SELECT id, title, summary, source_name, published_date, published "
        "FROM items "
        "WHERE classified = 0 OR classified IS NULL "
        "ORDER BY (published_date IS NULL OR published_date = ''), "
        "published_date DESC, id DESC "
        "LIMIT ?"
    )
    return conn.execute(sql, (limit,)).fetchall()


def build_prompt(row) -> str:
    summary = (row["summary"] or "").strip()
    if len(summary) > SUMMARY_CHAR_LIMIT:
        summary = summary[:SUMMARY_CHAR_LIMIT] + " [...]"
    return PROMPT_TEMPLATE.format(
        title=(row["title"] or "").strip() or "(no title)",
        source=row["source_name"] or "(unknown source)",
        published=row["published_date"] or row["published"] or "(unknown date)",
        summary=summary or "(no summary available)",
    )


def call_claude_cli(claude_bin: str, prompt: str, model: str) -> str:
    result = subprocess.run(
        [claude_bin, "-p", prompt, "--model", model],
        capture_output=True,
        text=True,
        timeout=CLI_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"claude CLI exited with code {result.returncode}: "
            f"{(result.stderr or '').strip()[:500]}"
        )
    stdout = (result.stdout or "").strip()
    if not stdout:
        raise RuntimeError("claude CLI returned empty output")
    return stdout


def clamp_score(value) -> int:
    score = int(round(float(value)))
    return max(0, min(10, score))


def parse_classification(raw_text: str) -> dict:
    """Defensively parse the CLI response into a classification dict.

    Tries strict JSON first; falls back to pulling a bare 0-10 integer out
    of the text. Raises ValueError if no score can be recovered at all.
    """
    match = _JSON_OBJECT_RE.search(raw_text)
    if match:
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            data = None
        if isinstance(data, dict) and "score" in data:
            score = clamp_score(data["score"])
            is_relevant = data.get("is_relevant")
            if is_relevant is None:
                is_relevant = score >= 4
            return {
                "score": score,
                "is_relevant": 1 if is_relevant else 0,
                "company": str(data.get("company") or "").strip(),
                "country": str(data.get("country") or "").strip(),
                "project_type": str(data.get("project_type") or "").strip(),
                "summary": str(data.get("summary") or "").strip(),
            }

    # Fallback: no usable JSON — grab the first bare 0-10 number in the text.
    fallback = _FALLBACK_SCORE_RE.search(raw_text)
    if fallback:
        score = clamp_score(fallback.group(1))
        return {
            "score": score,
            "is_relevant": 1 if score >= 4 else 0,
            "company": "",
            "country": "",
            "project_type": "",
            "summary": "",
        }

    raise ValueError(f"could not parse a score from CLI output: {raw_text[:300]!r}")


def update_item(conn, item_id: int, result: dict) -> None:
    conn.execute(
        """
        UPDATE items
        SET classified = 1,
            score = ?,
            is_relevant = ?,
            company = ?,
            ai_country = ?,
            project_type = ?,
            ai_summary = ?
        WHERE id = ?
        """,
        (
            result["score"],
            result["is_relevant"],
            result["company"],
            result["country"],
            result["project_type"],
            result["summary"],
            item_id,
        ),
    )
    conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Classify unclassified intel.db items via the local Claude CLI"
    )
    parser.add_argument("--limit", type=int, default=50,
                         help="max number of unclassified items to process (default 50)")
    parser.add_argument("--model", default="haiku",
                         help="model to pass to 'claude --model' (default haiku)")
    args = parser.parse_args()

    if args.limit <= 0:
        sys.exit("ERROR: --limit must be a positive integer")

    claude_bin = find_claude_cli()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    ensure_schema(conn)
    ensure_columns(conn)

    rows = fetch_unclassified(conn, args.limit)
    if not rows:
        print("No unclassified items found. Nothing to do.")
        conn.close()
        return

    print(f"Classifying {len(rows)} item(s) with model '{args.model}' ...")
    print("-" * 70)

    success_count = 0
    fail_count = 0
    score_bucket = {"0-3": 0, "4-7": 0, "8-10": 0}

    for i, row in enumerate(rows, start=1):
        title_preview = (row["title"] or "(no title)").strip()[:80]
        prefix = f"[{i}/{len(rows)}] id={row['id']}"

        try:
            prompt = build_prompt(row)
            raw = call_claude_cli(claude_bin, prompt, args.model)
            result = parse_classification(raw)
        except (subprocess.TimeoutExpired, RuntimeError, ValueError) as exc:
            print(f"{prefix} ERROR: {exc}")
            print(f"           title: {title_preview}")
            fail_count += 1
            continue
        except Exception as exc:  # noqa: BLE001 - fail loudly, never swallow silently
            print(f"{prefix} ERROR (unexpected {type(exc).__name__}): {exc}")
            print(f"           title: {title_preview}")
            fail_count += 1
            continue

        try:
            update_item(conn, row["id"], result)
        except sqlite3.Error as exc:
            print(f"{prefix} ERROR: failed to write to DB: {exc}")
            fail_count += 1
            continue

        success_count += 1
        score = result["score"]
        if score >= 8:
            score_bucket["8-10"] += 1
        elif score >= 4:
            score_bucket["4-7"] += 1
        else:
            score_bucket["0-3"] += 1

        rel = "Y" if result["is_relevant"] else "N"
        company = result["company"] or "-"
        print(f"{prefix} score={score:2d} relevant={rel} company={company} - {title_preview}")

    conn.close()

    print("-" * 70)
    print(f"Done. {success_count} classified, {fail_count} failed, "
          f"{len(rows)} total attempted.")
    if success_count:
        print("Score distribution (of successfully classified items):")
        print(f"  0-3  (reject) : {score_bucket['0-3']}")
        print(f"  4-7  (maybe)  : {score_bucket['4-7']}")
        print(f"  8-10 (lead)   : {score_bucket['8-10']}")

    if fail_count > 0:
        print(f"FAILED: {fail_count} item(s) could not be classified. "
              f"See errors above.", file=sys.stderr)
        sys.exit(1)

    if success_count == 0:
        # Should be unreachable (rows was non-empty and every failure exits
        # above), but guard explicitly so a silent zero-scored run is
        # impossible even if the logic above changes later.
        print("ERROR: no items were classified.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
