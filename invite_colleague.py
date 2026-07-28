"""
invite_colleague.py — admin tool for the private dashboard's invite-only
access list (see web/SETUP.md for the full picture).

There is deliberately NO public "sign up" anywhere in the auth gate. The
only way an account can ever see the dashboard is:
  1. You run this script for their email -> Supabase sends them an invite
     email (they click it, set a password on /set-password).
  2. Their email is added to the `allowed_emails` table -> the dashboard's
     server-side gate (web/api/dashboard.js) actually checks this on every
     request, independent of whether their Supabase account exists.

Both steps happen together here so you can't end up with one without the
other. Revoking access is the mirror operation (--revoke) and only touches
the allowlist row — it does not delete their Supabase account, so
re-inviting later is instant.

Usage
-----
    python invite_colleague.py bob@example.com
    python invite_colleague.py bob@example.com --label "Bob - Sales"
    python invite_colleague.py --revoke bob@example.com
    python invite_colleague.py --list
"""

import argparse
import re
import sys
from pathlib import Path

from supabase import create_client
from supabase_auth.errors import AuthApiError
from postgrest.exceptions import APIError

ENV_PATH = Path(__file__).with_name(".env")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


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


def get_client(env: dict):
    url = env.get("SUPABASE_URL")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not service_key:
        sys.exit(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env\n"
            "       (the service role key — never the anon key — is required here;\n"
            "        see web/SETUP.md)."
        )
    return create_client(url, service_key)


def invite(client, env: dict, email: str, label: str | None) -> None:
    site_url = env.get("DASHBOARD_SITE_URL", "").rstrip("/")
    options = {}
    if site_url:
        options["redirect_to"] = f"{site_url}/set-password"

    print(f"Inviting {email} ...")
    try:
        client.auth.admin.invite_user_by_email(email, options or None)
        print("  invite email sent.")
    except AuthApiError as exc:
        msg = (exc.message or "").lower()
        if "already registered" in msg or "already exists" in msg or exc.code == "email_exists":
            print("  account already exists for this email (no new invite email sent) — "
                  "continuing to make sure they're on the allowlist.")
        else:
            sys.exit(f"ERROR: could not send invite: {exc.message} (status {exc.status})")

    try:
        client.table("allowed_emails").insert({"email": email, "label": label}).execute()
        print(f"  added to allowed_emails.")
    except APIError as exc:
        if exc.code == "23505":  # unique_violation
            print("  already on allowed_emails — nothing to change.")
        else:
            sys.exit(f"ERROR: could not update allowed_emails: {exc.message}")

    print(f"Done. {email} can now sign in once they set a password from the invite email.")


def revoke(client, email: str) -> None:
    print(f"Revoking {email} ...")
    try:
        result = client.table("allowed_emails").delete().eq("email", email).execute()
    except APIError as exc:
        sys.exit(f"ERROR: could not update allowed_emails: {exc.message}")

    if not result.data:
        print("  that email wasn't on the allowlist — nothing to change.")
    else:
        print(f"  removed from allowed_emails. Their Supabase account still exists but "
              f"the dashboard will now refuse them — re-invite any time to restore access.")


def list_allowed(client) -> None:
    try:
        result = client.table("allowed_emails").select("email,label,added_at").order("added_at").execute()
    except APIError as exc:
        sys.exit(f"ERROR: could not read allowed_emails: {exc.message}")

    rows = result.data or []
    if not rows:
        print("allowed_emails is empty — nobody can currently sign in.")
        return
    print(f"{len(rows)} approved email(s):")
    for row in rows:
        label = f"  ({row['label']})" if row.get("label") else ""
        print(f"  - {row['email']}{label}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("email", nargs="?", help="email address to invite")
    group.add_argument("--revoke", metavar="EMAIL", help="remove an email from the allowlist")
    group.add_argument("--list", action="store_true", help="print the current allowlist")
    parser.add_argument("--label", help="optional note stored alongside an invited email, e.g. 'Bob - Sales'")
    args = parser.parse_args()

    if not args.email and not args.revoke and not args.list:
        parser.error("provide an email to invite, or use --revoke EMAIL / --list")

    env = load_env(ENV_PATH)
    client = get_client(env)

    if args.list:
        list_allowed(client)
        return

    if args.revoke:
        email = args.revoke.strip().lower()
        if not EMAIL_RE.match(email):
            sys.exit(f"ERROR: '{args.revoke}' doesn't look like a valid email address")
        revoke(client, email)
        return

    email = args.email.strip().lower()
    if not EMAIL_RE.match(email):
        sys.exit(f"ERROR: '{args.email}' doesn't look like a valid email address")
    invite(client, env, email, args.label)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
