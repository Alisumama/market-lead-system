"""
init_db.py — create / upgrade the intel.db SQLite database.

Run once to set up the database:
    python init_db.py

It is safe to run repeatedly (CREATE TABLE IF NOT EXISTS). collect.py also
calls ensure_schema() on every run, so you do not strictly have to run this
first — but running it once makes the setup explicit and lets you confirm the
schema before collecting.

Schema
------
items            one row per unique collected item (deduplicated by url_hash)
collection_log   one row per (run, source) — the health check / LOG tab data
"""

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).with_name("intel.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    url_hash      TEXT    NOT NULL UNIQUE,   -- sha256 of the item link (dedup key)
    url           TEXT    NOT NULL,
    title         TEXT,
    summary       TEXT,                       -- raw feed summary/description
    published     TEXT,                       -- raw publish date string from the feed
    published_date TEXT,                      -- normalized YYYY-MM-DD ('' if undetectable)
    source_name   TEXT,
    source_type   TEXT,                       -- rss | google_alert
    language      TEXT,
    country       TEXT,
    collected_at  TEXT    NOT NULL,           -- ISO timestamp we first stored it
    -- Phase 2 (classify.py) fills these; left empty in Phase 1:
    classified    INTEGER NOT NULL DEFAULT 0,
    is_relevant   INTEGER,
    score         INTEGER,
    company       TEXT,
    project_type  TEXT,
    ai_summary    TEXT
);

CREATE INDEX IF NOT EXISTS idx_items_classified ON items(classified);
CREATE INDEX IF NOT EXISTS idx_items_country    ON items(country);
CREATE INDEX IF NOT EXISTS idx_items_collected  ON items(collected_at);
-- NOTE: the published_date index is created in ensure_columns(), because on an
-- existing DB that column is added by ALTER TABLE and does not exist yet here.

CREATE TABLE IF NOT EXISTS collection_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    run_at       TEXT    NOT NULL,            -- ISO timestamp of the collection run
    source_name  TEXT    NOT NULL,
    items_found  INTEGER NOT NULL DEFAULT 0,  -- entries seen in the feed
    items_new    INTEGER NOT NULL DEFAULT 0,  -- entries that were new (inserted)
    status       TEXT    NOT NULL,            -- ok | error | skipped
    error        TEXT                          -- error message if status = error
);

CREATE INDEX IF NOT EXISTS idx_log_run ON collection_log(run_at);
"""


def ensure_schema(conn: sqlite3.Connection) -> None:
    """Create tables/indexes if they do not already exist."""
    conn.executescript(SCHEMA)
    conn.commit()


# Columns added after the original schema shipped. ensure_columns() lets an
# existing intel.db pick them up without a rebuild (CREATE TABLE IF NOT EXISTS
# never alters an existing table).
_ADDED_COLUMNS = (
    ("ai_country", "TEXT"),       # AI-detected project country (classify.py)
    ("published_date", "TEXT"),   # normalized YYYY-MM-DD (collect.py)
)


def ensure_columns(conn: sqlite3.Connection) -> None:
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    if "items" not in tables:
        return  # nothing to migrate yet (call ensure_schema first)
    have = {r[1] for r in conn.execute("PRAGMA table_info(items)")}
    for col, decl in _ADDED_COLUMNS:
        if col not in have:
            conn.execute(f"ALTER TABLE items ADD COLUMN {col} {decl}")
    # Safe now that published_date is guaranteed to exist.
    conn.execute("CREATE INDEX IF NOT EXISTS idx_items_published "
                 "ON items(published_date)")
    conn.commit()


def parse_date_to_iso(raw: str | None) -> str:
    """Best-effort parse of an RSS/Atom date string -> 'YYYY-MM-DD' (or '')."""
    if not raw:
        return ""
    raw = raw.strip()
    # RFC 2822 (RSS <pubDate>, e.g. 'Mon, 15 Jun 2015 10:30:00 GMT')
    try:
        import email.utils
        dt = email.utils.parsedate_to_datetime(raw)
        if dt:
            return dt.strftime("%Y-%m-%d")
    except (TypeError, ValueError, IndexError):
        pass
    # ISO 8601 (Atom <published>/<updated>, e.g. '2015-06-15T10:30:00Z')
    from datetime import datetime
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).strftime("%Y-%m-%d")
    except ValueError:
        pass
    # Bare 'YYYY-MM-DD' prefix as a last resort
    import re
    m = re.match(r"(\d{4}-\d{2}-\d{2})", raw)
    return m.group(1) if m else ""


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    try:
        ensure_schema(conn)
        print(f"OK  intel.db ready at: {DB_PATH}")
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )]
        print("    tables:", ", ".join(tables))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
