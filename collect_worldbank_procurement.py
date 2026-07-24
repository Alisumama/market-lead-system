"""
collect_worldbank_procurement.py — World Bank PROCUREMENT NOTICES for target markets.

Complements collect_worldbank.py (which pulls project *documents* from the WDS
API). This one hits the procurement-notices API:
    https://search.worldbank.org/api/v2/procnotices
querying milling/flour/grain-processing terms, filtered to a fixed list of
target countries, and inserts each notice into intel.db with source_type
"WorldBank" so it flows through classify.py / export.py / the dashboard.

These are ACTUAL tenders/bids (e.g. "Supply and installation of milling
equipment") — the highest-quality lead type. Standard library only.

Usage:
    python collect_worldbank_procurement.py
    python collect_worldbank_procurement.py --rows 60 --verbose
    python collect_worldbank_procurement.py --qterm "milling OR flour"
"""

import argparse
import hashlib
import json
import re
import sqlite3
import urllib.parse
import urllib.request
from datetime import datetime, timezone

from init_db import DB_PATH, ensure_schema, ensure_columns

PROCNOTICES_ENDPOINT = "https://search.worldbank.org/api/v2/procnotices"
DETAIL_URL = "https://projects.worldbank.org/en/projects-operations/procurement-detail/{id}"
USER_AGENT = "BastakMarketIntel/1.0 (+bastakinstruments@gmail.com)"
SOURCE_NAME = "World Bank Procurement Notices"
SOURCE_TYPE = "WorldBank"

# Target markets: exact project_ctry_name the API expects -> our country tag.
COUNTRIES = [
    ("Pakistan", "pk"),
    ("Nigeria", "ng"),
    ("Kenya", "ke"),
    ("Egypt, Arab Republic of", "eg"),
    ("Ethiopia", "et"),
    ("Tanzania", "tz"),
    ("Uganda", "ug"),
    ("Mozambique", "mz"),
    ("Kazakhstan", "kz"),
]

# Moderate net: single words "milling"/"flour" catch e.g. "Rice Milling
# Equipment"; phrases catch grain-processing/storage. Avoids bare "grain"/
# "cereal"/"wheat" which flood in food-distribution notices.
DEFAULT_QTERM = (
    '"flour mill" OR "flour milling" OR milling OR flour OR "grain mill" OR '
    '"grain milling" OR "grain silo" OR "grain storage" OR "wheat mill"'
)

_TAG_RE = re.compile(r"<[^>]+>")


def url_hash(url: str) -> str:
    return hashlib.sha256(url.strip().encode("utf-8")).hexdigest()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def strip_html(text: str) -> str:
    return re.sub(r"\s+", " ", _TAG_RE.sub(" ", text or "")).strip()


def parse_notice_date(raw: str) -> str:
    """'02-Jun-2026' -> '2026-06-02' (or '' if unparseable)."""
    raw = (raw or "").strip()
    try:
        return datetime.strptime(raw, "%d-%b-%Y").strftime("%Y-%m-%d")
    except ValueError:
        return ""


def fetch_country(country_name: str, qterm: str, rows: int) -> list[dict]:
    params = {
        "format": "json", "rows": str(rows), "qterm": qterm,
        "project_ctry_name_exact": country_name,
    }
    url = PROCNOTICES_ENDPOINT + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.load(resp)
    return data.get("total", 0), data.get("procnotices", []) or []


def main() -> None:
    ap = argparse.ArgumentParser(description="Collect World Bank procurement notices into intel.db")
    ap.add_argument("--rows", type=int, default=40, help="max notices per country, newest first (default 40)")
    ap.add_argument("--qterm", default=DEFAULT_QTERM, help="override the search query")
    ap.add_argument("--verbose", action="store_true", help="print each stored notice")
    args = ap.parse_args()

    # Busy timeout so this coexists with a concurrent classify.py writing to the DB.
    conn = sqlite3.connect(DB_PATH, timeout=30)
    ensure_schema(conn)
    ensure_columns(conn)

    collected_at = now_iso()
    grand_new = 0

    for country_name, code in COUNTRIES:
        try:
            total, notices = fetch_country(country_name, args.qterm, args.rows)
        except Exception as exc:  # noqa: BLE001
            print(f"  {country_name}: API ERROR {exc}")
            continue

        new_here = 0
        for n in notices:
            nid = (n.get("id") or "").strip()
            if not nid:
                continue
            link = DETAIL_URL.format(id=nid)
            title = (n.get("bid_description") or n.get("project_name") or "").strip()
            proj = (n.get("project_name") or "").strip()
            ntype = (n.get("notice_type") or "").strip()
            method = (n.get("procurement_method_name") or "").strip()
            body = strip_html(n.get("notice_text", ""))[:400]
            summary = " · ".join(x for x in (ntype, method, proj) if x)
            if body:
                summary = f"{summary} — {body}" if summary else body

            try:
                conn.execute(
                    """INSERT INTO items
                         (url_hash, url, title, summary, published, published_date,
                          source_name, source_type, language, country, collected_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (url_hash(link), link, title, summary,
                     (n.get("noticedate") or "").strip(), parse_notice_date(n.get("noticedate")),
                     SOURCE_NAME, SOURCE_TYPE,
                     (n.get("notice_lang_name") or "en").strip(), code, collected_at),
                )
                new_here += 1
                if args.verbose:
                    print(f"    + [{code}] {title[:66]}")
            except sqlite3.IntegrityError:
                pass  # already stored

        conn.commit()
        grand_new += new_here
        print(f"  {country_name:28} matched {total:>4}, pulled {len(notices):>3}, {new_here:>3} new")

    conn.close()
    print(f"\nDone. {grand_new} new procurement notice(s) inserted. Run classify.py next.")


if __name__ == "__main__":
    main()
