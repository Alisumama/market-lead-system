"""
collect.py — Phase 1 collector for the Bastak Market Intelligence System.

What it does
------------
1. Reads sources.yaml (the registry you edit).
2. For every ENABLED source of type `rss` or `google_alert`, fetches the feed
   with feedparser.
3. Stores each new entry in intel.db, deduplicated by a SHA-256 hash of the
   item URL (so the same article appearing across weeks / across sites is
   stored once).
4. Writes one collection_log row per source so you can see, per day, whether a
   source is still producing items (the "scrapers break silently" safeguard).

What it does NOT do (later phases)
----------------------------------
- type `html` / `tender` sources are SKIPPED (Phase 3 structured scrapers).
- No AI classification / scoring (Phase 2: classify.py).
- No Excel export (export.py) and no notifications (Phase 2: notify.py).

Usage
-----
    python collect.py            # collect from all enabled rss/google_alert sources
    python collect.py --verbose  # print each new item title as it is stored
"""

import argparse
import hashlib
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import feedparser
import yaml

from init_db import DB_PATH, ensure_schema, ensure_columns, parse_date_to_iso

SOURCES_PATH = Path(__file__).with_name("sources.yaml")

# Be a polite crawler (Risks & Rules section of the spec: throttle, identify).
USER_AGENT = "BastakMarketIntel/1.0 (+contact: bastakinstruments@gmail.com)"
THROTTLE_SECONDS = 2.5            # pause between sources
RSS_TYPES = {"rss", "google_alert"}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def url_hash(url: str) -> str:
    return hashlib.sha256(url.strip().encode("utf-8")).hexdigest()


def load_sources() -> list[dict]:
    if not SOURCES_PATH.exists():
        sys.exit(f"ERROR: {SOURCES_PATH.name} not found next to collect.py")
    with SOURCES_PATH.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    sources = data.get("sources") or []
    if not isinstance(sources, list):
        sys.exit("ERROR: sources.yaml must contain a top-level 'sources:' list")
    return sources


def entry_link(entry) -> str | None:
    """Best-effort extraction of a stable URL from a feed entry."""
    link = entry.get("link")
    if link:
        return link.strip()
    # Some feeds only expose links[] or an id that happens to be a URL.
    for lnk in entry.get("links", []) or []:
        href = lnk.get("href")
        if href:
            return href.strip()
    ident = entry.get("id")
    if ident and ident.startswith("http"):
        return ident.strip()
    return None


def entry_published(entry) -> str:
    """Human-readable published date if the feed provides one."""
    for key in ("published", "updated", "created"):
        val = entry.get(key)
        if val:
            return str(val)
    return ""


def entry_published_date(entry) -> str:
    """Normalized 'YYYY-MM-DD' publication date, or '' if none detectable.

    Prefer feedparser's parsed struct_time (handles both RSS and Atom); fall
    back to parsing the raw string ourselves.
    """
    for key in ("published_parsed", "updated_parsed"):
        t = entry.get(key)
        if t:
            try:
                return time.strftime("%Y-%m-%d", t)
            except (TypeError, ValueError):
                pass
    return parse_date_to_iso(entry_published(entry))


def collect_source(conn: sqlite3.Connection, src: dict, verbose: bool) -> tuple[int, int]:
    """Fetch one feed, insert new items. Returns (items_found, items_new)."""
    url = src.get("url", "")
    feed = feedparser.parse(url, agent=USER_AGENT)

    # feedparser sets bozo=1 on malformed feeds; a hard failure has no entries.
    if feed.bozo and not feed.entries:
        raise RuntimeError(str(feed.get("bozo_exception", "unreadable feed")))

    entries = feed.entries or []
    new_count = 0
    collected_at = now_iso()

    for entry in entries:
        link = entry_link(entry)
        if not link:
            continue
        h = url_hash(link)
        try:
            conn.execute(
                """
                INSERT INTO items
                    (url_hash, url, title, summary, published, published_date,
                     source_name, source_type, language, country, collected_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    h,
                    link,
                    (entry.get("title") or "").strip(),
                    (entry.get("summary") or "").strip(),
                    entry_published(entry),
                    entry_published_date(entry),
                    src.get("name", ""),
                    src.get("type", ""),
                    src.get("language", ""),
                    src.get("country", ""),
                    collected_at,
                ),
            )
            new_count += 1
            if verbose:
                print(f"      + {entry.get('title', '(no title)')[:90]}")
        except sqlite3.IntegrityError:
            # url_hash already present -> duplicate, skip.
            pass

    conn.commit()
    return len(entries), new_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect RSS items into intel.db")
    parser.add_argument("--verbose", action="store_true",
                        help="print each newly stored item title")
    args = parser.parse_args()

    conn = sqlite3.connect(DB_PATH)
    ensure_schema(conn)
    ensure_columns(conn)

    sources = load_sources()
    run_at = now_iso()
    total_new = 0
    active = [s for s in sources if s.get("enabled")]

    print(f"Collection run {run_at}")
    print(f"{len(active)} enabled source(s) in registry\n")

    for src in active:
        name = src.get("name", "(unnamed)")
        stype = (src.get("type") or "").lower()

        # Phase 1 handles RSS only; log others as skipped so they stay visible.
        if stype not in RSS_TYPES:
            print(f"  - {name}: skipped (type '{stype}' — later phase)")
            conn.execute(
                "INSERT INTO collection_log "
                "(run_at, source_name, items_found, items_new, status, error) "
                "VALUES (?, ?, 0, 0, 'skipped', ?)",
                (run_at, name, f"type '{stype}' not collected in Phase 1"),
            )
            conn.commit()
            continue

        url = src.get("url", "")
        if not url or url.startswith("PLACEHOLDER"):
            print(f"  - {name}: skipped (no real url set yet)")
            conn.execute(
                "INSERT INTO collection_log "
                "(run_at, source_name, items_found, items_new, status, error) "
                "VALUES (?, ?, 0, 0, 'skipped', 'placeholder url')",
                (run_at, name),
            )
            conn.commit()
            continue

        try:
            found, new = collect_source(conn, src, args.verbose)
            total_new += new
            print(f"  - {name}: {found} in feed, {new} new")
            conn.execute(
                "INSERT INTO collection_log "
                "(run_at, source_name, items_found, items_new, status, error) "
                "VALUES (?, ?, ?, ?, 'ok', NULL)",
                (run_at, name, found, new),
            )
            conn.commit()
        except Exception as exc:  # noqa: BLE001 - we want to log & continue
            print(f"  - {name}: ERROR {exc}")
            conn.execute(
                "INSERT INTO collection_log "
                "(run_at, source_name, items_found, items_new, status, error) "
                "VALUES (?, ?, 0, 0, 'error', ?)",
                (run_at, name, str(exc)),
            )
            conn.commit()

        time.sleep(THROTTLE_SECONDS)

    total_items = conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
    conn.close()

    print(f"\nDone. {total_new} new item(s) this run; {total_items} total in intel.db.")


if __name__ == "__main__":
    main()
