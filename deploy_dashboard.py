"""
deploy_dashboard.py — publish the freshly built dashboard.html to the
PRIVATE Supabase Storage bucket the auth gate (web/api/dashboard.js) serves
from.

This is the ONLY thing that leaves your machine when the dashboard is
"published": the finished HTML, pushed straight into private cloud storage
via an authenticated API call using the Supabase service role key from
.env. It is never written to a public URL, never committed to git, and
never touches the auth layer's own code (web/) — that's what lets the auth
gate stay in place even though build_dashboard.py overwrites dashboard.html
from scratch every run.

Run this right after build_dashboard.py (run_daily.bat already does this).

Usage
-----
    python deploy_dashboard.py
"""

import sys
from pathlib import Path

from storage3.exceptions import StorageApiError
from supabase import create_client

ENV_PATH = Path(__file__).with_name(".env")
DASHBOARD_PATH = Path(__file__).with_name("dashboard.html")


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


def main() -> None:
    if not DASHBOARD_PATH.exists():
        sys.exit(f"ERROR: {DASHBOARD_PATH.name} not found — run build_dashboard.py first.")

    env = load_env(ENV_PATH)
    url = env.get("SUPABASE_URL")
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not service_key:
        sys.exit(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env\n"
            "       (see web/SETUP.md). The dashboard was built locally but NOT\n"
            "       published — the previously published version is still live."
        )

    bucket = env.get("SUPABASE_DASHBOARD_BUCKET", "dashboard-private")
    storage_path = env.get("SUPABASE_DASHBOARD_PATH", "dashboard.html")

    html_bytes = DASHBOARD_PATH.read_bytes()
    print(f"Uploading {DASHBOARD_PATH.name} ({len(html_bytes):,} bytes) "
          f"to private bucket '{bucket}' as '{storage_path}' ...")

    client = create_client(url, service_key)
    try:
        client.storage.from_(bucket).upload(
            storage_path,
            html_bytes,
            file_options={"content-type": "text/html; charset=utf-8", "upsert": "true"},
        )
    except StorageApiError as exc:
        sys.exit(
            f"ERROR: upload failed: {exc}\n"
            f"       If this says the bucket doesn't exist, complete the Storage\n"
            f"       setup step in web/SETUP.md first. The previously published\n"
            f"       version (if any) is still live and unaffected."
        )
    except Exception as exc:  # noqa: BLE001 - fail loudly, never swallow silently
        sys.exit(f"ERROR: unexpected failure ({type(exc).__name__}): {exc}")

    print("Done. The live dashboard now reflects this build.")


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
