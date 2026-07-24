"""
collect_email.py — pull leads out of Gmail (LinkedIn + Google Alerts emails).

Connects to Gmail over IMAP using GMAIL_ADDRESS / GMAIL_APP_PASSWORD from .env,
reads UNREAD messages from the configured senders, extracts headline + link
(+ company name when detectable), and inserts them into intel.db with
source_type "LinkedIn" or "GoogleAlert" so they flow through classify.py and
export.py exactly like RSS items. Processed emails are marked read.

Uses only the Python standard library (imaplib, email, html.parser) — no extra
dependencies and no Anthropic API.

Modes
-----
    python collect_email.py --test    # connect + COUNT unread per sender only.
                                       # Read-only: inserts nothing, marks nothing.
    python collect_email.py           # full run: extract, insert new items,
                                       # then mark the processed emails as read.
    python collect_email.py --limit 20  # cap emails processed per sender

ALWAYS run --test first to confirm the connection and see the counts.
"""

import argparse
import email
import hashlib
import imaplib
import re
import sqlite3
import sys
import urllib.parse
from datetime import datetime, timezone
from email.header import decode_header
from html.parser import HTMLParser
from pathlib import Path

from init_db import DB_PATH, ensure_schema, ensure_columns, parse_date_to_iso

ENV_PATH = Path(__file__).with_name(".env")
IMAP_HOST = "imap.gmail.com"
MAILBOX = "INBOX"

# sender-domain substring  ->  source_type stored in intel.db
# NOTE: real Google Alerts email is sent from "googlealerts-noreply@google.com".
# Both patterns are included so the search works whichever address you receive.
SENDERS = {
    "linkedin.com": "LinkedIn",
    "googlealerts.com": "GoogleAlert",
    "googlealerts-noreply@google.com": "GoogleAlert",
}

# From-addresses to skip even if they match a monitored domain — these are
# account/security notices, never sales leads. Matched as case-insensitive
# substrings of the email's From header.
EXCLUDE_SENDERS = {
    "security-noreply@",
    "password-noreply@",
    "privacy-noreply@",
    "security@",
    "account-noreply@",
}

# Anchor text we never want to treat as a headline.
BOILERPLATE = {
    "flag as irrelevant", "see more results", "edit this alert", "rss feed",
    "create an alert", "unsubscribe", "view all", "see more", "manage alerts",
    "manage your alerts", "help", "google", "google alerts",
}


# --------------------------------------------------------------------------- #
# .env
# --------------------------------------------------------------------------- #
def load_env(path: Path) -> dict:
    env = {}
    if not path.exists():
        return env
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        env[key.strip()] = val.strip()
    return env


# --------------------------------------------------------------------------- #
# small helpers
# --------------------------------------------------------------------------- #
def url_hash(url: str) -> str:
    return hashlib.sha256(url.strip().encode("utf-8")).hexdigest()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def decode_hdr(value: str | None) -> str:
    if not value:
        return ""
    out = []
    for txt, enc in decode_header(value):
        if isinstance(txt, bytes):
            out.append(txt.decode(enc or "utf-8", errors="replace"))
        else:
            out.append(txt)
    return "".join(out).strip()


class AnchorParser(HTMLParser):
    """Collect (href, anchor_text) pairs from an HTML body."""

    def __init__(self):
        super().__init__()
        self.anchors: list[tuple[str, str]] = []
        self._href = None
        self._buf: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._buf = []

    def handle_data(self, data):
        if self._href is not None:
            self._buf.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            self.anchors.append((self._href, " ".join("".join(self._buf).split())))
            self._href = None
            self._buf = []


def unwrap_google(href: str) -> str | None:
    """Google Alerts wraps real links as google.com/url?...&url=REAL — unwrap it."""
    if "google.com/url" in href:
        params = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
        for key in ("url", "q"):
            if params.get(key):
                return params[key][0]
        return None
    if href.startswith("http") and "google.com" not in href:
        return href
    return None


def is_excluded(from_header: str) -> bool:
    low = (from_header or "").lower()
    return any(bad in low for bad in EXCLUDE_SENDERS)


def extract_company(text: str) -> str:
    """Light heuristic; classify.py does the authoritative extraction."""
    m = re.search(r"\bat\s+([A-Z][\w&.\-]+(?:\s+[A-Z][\w&.\-]+){0,3})", text)
    return m.group(1).strip() if m else ""


def get_html_body(msg) -> str:
    """Return the HTML body (preferred) or plain text, decoded to str."""
    html_body, text_body = "", ""
    parts = msg.walk() if msg.is_multipart() else [msg]
    for part in parts:
        if "attachment" in str(part.get("Content-Disposition") or ""):
            continue
        ctype = part.get_content_type()
        if ctype not in ("text/html", "text/plain"):
            continue
        raw = part.get_payload(decode=True)
        if raw is None:
            continue
        charset = part.get_content_charset() or "utf-8"
        try:
            decoded = raw.decode(charset, errors="replace")
        except LookupError:
            decoded = raw.decode("utf-8", errors="replace")
        if ctype == "text/html" and not html_body:
            html_body = decoded
        elif ctype == "text/plain" and not text_body:
            text_body = decoded
    return html_body or text_body


def extract_items(msg, source_type: str) -> list[tuple[str, str, str]]:
    """Return list of (headline, company, url) tuples from one email."""
    subject = decode_hdr(msg.get("Subject"))
    body = get_html_body(msg)
    anchors = []
    if body and "<a" in body.lower():
        p = AnchorParser()
        p.feed(body)
        anchors = p.anchors

    items: list[tuple[str, str, str]] = []
    seen_urls: set[str] = set()

    for href, atext in anchors:
        if source_type == "GoogleAlert":
            url = unwrap_google(href)
        else:  # LinkedIn
            url = href if "linkedin.com" in href else None
        if not url or url in seen_urls:
            continue
        clean_text = atext.strip()
        if not clean_text or clean_text.lower() in BOILERPLATE or len(clean_text) < 12:
            continue
        seen_urls.add(url)
        items.append((clean_text, extract_company(clean_text), url))
        if len(items) >= 15:
            break

    # Fallback: no usable link found -> one item keyed to the message itself.
    if not items:
        mid = decode_hdr(msg.get("Message-ID")) or url_hash(subject)
        items.append((subject, extract_company(subject), f"email://{mid}"))
    return items


# --------------------------------------------------------------------------- #
# IMAP
# --------------------------------------------------------------------------- #
def connect(env: dict) -> imaplib.IMAP4_SSL:
    addr = env.get("GMAIL_ADDRESS", "")
    # App passwords are shown in 4-char groups; the real value has no spaces.
    pwd = env.get("GMAIL_APP_PASSWORD", "").replace(" ", "")
    if not addr or not pwd:
        sys.exit("ERROR: GMAIL_ADDRESS / GMAIL_APP_PASSWORD are empty in .env")
    imap = imaplib.IMAP4_SSL(IMAP_HOST)
    imap.login(addr, pwd)
    return imap


def search_unseen(imap: imaplib.IMAP4_SSL, domain: str) -> list[bytes]:
    typ, data = imap.search(None, "UNSEEN", "FROM", domain)
    if typ != "OK" or not data or not data[0]:
        return []
    return data[0].split()


def header_preview(imap: imaplib.IMAP4_SSL, num: bytes) -> tuple[str, str]:
    """Fetch Subject/From WITHOUT marking the message read (BODY.PEEK)."""
    typ, data = imap.fetch(num, "(BODY.PEEK[HEADER.FIELDS (SUBJECT FROM)])")
    if typ != "OK" or not data or not data[0]:
        return "", ""
    msg = email.message_from_bytes(data[0][1])
    return decode_hdr(msg.get("Subject")), decode_hdr(msg.get("From"))


# --------------------------------------------------------------------------- #
# modes
# --------------------------------------------------------------------------- #
def run_test(env: dict) -> None:
    print(f"Connecting to {IMAP_HOST} as {env.get('GMAIL_ADDRESS','')} ...")
    imap = connect(env)
    print("  login OK")
    imap.select(MAILBOX, readonly=True)   # read-only: cannot change flags

    grand_total = 0
    grand_excluded = 0
    for domain, stype in SENDERS.items():
        nums = search_unseen(imap, domain)
        excluded = 0
        for num in nums:
            _, frm = header_preview(imap, num)
            if is_excluded(frm):
                excluded += 1
        keep = len(nums) - excluded
        grand_total += keep
        grand_excluded += excluded
        note = f" ({excluded} excluded as account/security mail)" if excluded else ""
        print(f"\n[{stype}] FROM ~'{domain}': {len(nums)} unread, {keep} to process{note}")
        for num in nums[:3]:
            subj, frm = header_preview(imap, num)
            tag = "  [EXCLUDED]" if is_excluded(frm) else ""
            print(f"    - {subj[:70]}{tag}")
            print(f"      from: {frm[:70]}")

    imap.logout()
    print(f"\nTOTAL to process: {grand_total}  (excluded {grand_excluded})")
    print("TEST MODE — nothing inserted, nothing marked read.")


def run_collect(env: dict, limit: int | None) -> None:
    imap = connect(env)
    imap.select(MAILBOX)   # read-write so we can set \Seen after processing

    conn = sqlite3.connect(DB_PATH)
    ensure_schema(conn)
    ensure_columns(conn)

    total_new = 0
    total_emails = 0
    total_excluded = 0
    for domain, stype in SENDERS.items():
        nums = search_unseen(imap, domain)
        if limit:
            nums = nums[:limit]
        src_name = f"Email · {stype}"
        processed = 0
        for num in nums:
            # Peek the From header first (BODY.PEEK does NOT set \Seen) so that
            # excluded account/security mail is left untouched and stays unread.
            _, frm = header_preview(imap, num)
            if is_excluded(frm):
                total_excluded += 1
                continue  # leave unread; not a lead

            # A plain RFC822 fetch implicitly marks the message read — fine here,
            # since we only reach this for real leads we intend to process.
            typ, data = imap.fetch(num, "(RFC822)")
            if typ != "OK" or not data or not data[0]:
                continue
            msg = email.message_from_bytes(data[0][1])
            pub_raw = decode_hdr(msg.get("Date"))
            pub_date = parse_date_to_iso(pub_raw)
            inserted_here = 0
            for headline, company, url in extract_items(msg, stype):
                try:
                    conn.execute(
                        """INSERT INTO items
                             (url_hash, url, title, summary, published, published_date,
                              source_name, source_type, language, country,
                              collected_at, company)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', '', ?, ?)""",
                        (url_hash(url), url, headline, "", pub_raw, pub_date,
                         src_name, stype, now_iso(), company),
                    )
                    inserted_here += 1
                except sqlite3.IntegrityError:
                    pass  # already seen this url
            conn.commit()
            total_new += inserted_here
            total_emails += 1
            processed += 1
            imap.store(num, "+FLAGS", "\\Seen")   # mark read after processing
        print(f"[{stype}] processed {processed} email(s)")

    conn.close()
    imap.logout()
    print(f"\nDone. {total_emails} email(s) processed, {total_excluded} excluded "
          f"(account/security), {total_new} new item(s) inserted into intel.db.")
    if total_new:
        print("Run classify.py next to score them.")


def main() -> None:
    ap = argparse.ArgumentParser(description="Collect leads from Gmail (LinkedIn/Google Alerts)")
    ap.add_argument("--test", action="store_true",
                    help="connect and COUNT unread only; insert nothing, mark nothing")
    ap.add_argument("--limit", type=int, default=None, help="max emails per sender")
    args = ap.parse_args()

    env = load_env(ENV_PATH)
    try:
        if args.test:
            run_test(env)
        else:
            run_collect(env, args.limit)
    except imaplib.IMAP4.error as exc:
        sys.exit(f"IMAP error: {exc}  (check GMAIL_APP_PASSWORD and that IMAP is enabled in Gmail)")


if __name__ == "__main__":
    main()
