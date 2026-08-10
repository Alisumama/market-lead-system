"""
pipeline_health.py - emit a single HEARTBEAT summary at the end of every
run_daily.bat run, so a silent freeze is visible at a glance in daily_run.log.

Answers, in one place:
  * did every step run, and which ones failed or were skipped?
  * how many fresh leads are in the dashboard that was just built?
  * did the upload to the Supabase bucket ACTUALLY land? (checked by reading
    the object's timestamp back from Supabase, not by trusting an exit code)

Called by run_daily.bat with each step's exit code. Exit codes use the same
convention as the pipeline: 0 = ok, 2 = skipped (non-fatal), anything else =
failed, and -1 = the step never executed.

This script must NEVER take the pipeline down: every check is guarded, and a
heartbeat line is printed no matter what goes wrong inside it.

Usage (run_daily.bat does this for you)
---------------------------------------
    python pipeline_health.py --collect 0 --email 1 --wbproc 0 --classify 2 \
        --export 0 --build 0 --deploy 0
"""

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ENV_PATH = Path(__file__).with_name(".env")
DASHBOARD_PATH = Path(__file__).with_name("dashboard.html")

# How recently the bucket object must have been written for the deploy to count
# as having landed on THIS run rather than a previous one.
FRESH_UPLOAD_MINUTES = 30

# Steps whose failure does not stop the dashboard from publishing. A collector
# failing costs us data; it does not make the site stale.
NON_CRITICAL = ("collect", "email", "wbproc", "classify", "export")
# Steps that MUST succeed or the live site goes stale.
CRITICAL = ("build", "deploy")


def load_env(path: Path) -> dict:
    env = {}
    if not path.exists():
        return env
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        env[key.strip()] = val.strip()
    return env


def read_dashboard_facts() -> dict:
    """Fresh-lead count and build stamp from the dashboard that was just built."""
    facts = {"fresh": "?", "built": "?", "bytes": "?"}
    try:
        html = DASHBOARD_PATH.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        facts["error"] = f"could not read dashboard.html: {exc}"
        return facts
    facts["bytes"] = DASHBOARD_PATH.stat().st_size
    m = re.search(r'id="stat-fresh"[^>]*>(.*?)</div>', html, re.S)
    if m:
        facts["fresh"] = m.group(1).strip()
    m = re.search(r"(20\d{2}-\d{2}-\d{2} \d{2}:\d{2})", html)
    if m:
        facts["built"] = m.group(1)
    return facts


def check_bucket(env: dict) -> dict:
    """Read the object's timestamp back out of Supabase - the only real proof
    the upload landed where the live site actually looks."""
    out = {"ok": False, "bucket": env.get("SUPABASE_DASHBOARD_BUCKET", "dashboard-private")}
    url = env.get("SUPABASE_URL")
    key = env.get("SUPABASE_SERVICE_ROLE_KEY")
    name = env.get("SUPABASE_DASHBOARD_PATH", "dashboard.html")
    if not url or not key:
        out["detail"] = "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from .env"
        return out
    try:
        from supabase import create_client

        client = create_client(url, key)
        for obj in client.storage.from_(out["bucket"]).list():
            if obj.get("name") != name:
                continue
            meta = obj.get("metadata") or {}
            out["size"] = meta.get("size")
            stamp = obj.get("updated_at") or ""
            out["updated"] = stamp
            try:
                when = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
                age = (datetime.now(timezone.utc) - when).total_seconds() / 60.0
                out["age_min"] = round(age, 1)
                out["ok"] = age <= FRESH_UPLOAD_MINUTES
                if not out["ok"]:
                    out["detail"] = f"object is {age:.0f} min old - this run did not update it"
            except ValueError:
                out["ok"] = True  # object exists; timestamp just unparseable
                out["detail"] = "timestamp unparseable"
            return out
        out["detail"] = f"'{name}' not present in bucket '{out['bucket']}'"
    except Exception as exc:  # noqa: BLE001 - health check must never crash the run
        out["detail"] = f"{type(exc).__name__}: {exc}"
    return out


def label(rc: int) -> str:
    if rc == 0:
        return "ok"
    if rc == 2:
        return "skipped"
    if rc == -1:
        return "not-run"
    return f"FAILED(rc={rc})"


def main() -> None:
    p = argparse.ArgumentParser(description="Emit the run heartbeat line")
    for step in NON_CRITICAL + CRITICAL:
        p.add_argument(f"--{step}", type=int, default=-1)
    args = p.parse_args()

    steps = {step: getattr(args, step) for step in NON_CRITICAL + CRITICAL}

    ok = [s for s, rc in steps.items() if rc == 0]
    skipped = [s for s, rc in steps.items() if rc == 2]
    failed = [s for s, rc in steps.items() if rc not in (0, 2)]

    facts = read_dashboard_facts()
    bucket = check_bucket(load_env(ENV_PATH))

    # The site is only truly healthy if the dashboard was built AND the upload
    # is verifiably present and recent. Collectors failing is a degradation,
    # not an outage - the site still refreshes with the data we do have.
    critical_failed = [s for s in CRITICAL if steps[s] not in (0, 2)]
    if critical_failed or not bucket["ok"]:
        status = "BROKEN"
    elif failed or skipped:
        status = "DEGRADED"
    else:
        status = "HEALTHY"

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"HEARTBEAT {now} | status={status} | "
          f"steps ok={len(ok)} failed={len(failed)} skipped={len(skipped)}")
    print(f"  fresh_leads={facts['fresh']} | built={facts['built']} | "
          f"local_bytes={facts['bytes']}")
    deploy_word = "OK" if bucket["ok"] else "FAILED"
    line = (f"  deploy={deploy_word} bucket={bucket['bucket']} "
            f"size={bucket.get('size', '?')} updated={bucket.get('updated', '?')}")
    if "age_min" in bucket:
        line += f" (age {bucket['age_min']} min)"
    print(line)
    if bucket.get("detail"):
        print(f"  deploy_detail: {bucket['detail']}")
    if facts.get("error"):
        print(f"  dashboard_detail: {facts['error']}")
    print(f"  failed steps: {', '.join(failed) if failed else 'none'} | "
          f"skipped: {', '.join(skipped) if skipped else 'none'}")


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - always emit something
        print(f"HEARTBEAT {datetime.now():%Y-%m-%d %H:%M:%S} | status=UNKNOWN | "
              f"health check itself failed: {type(exc).__name__}: {exc}")
