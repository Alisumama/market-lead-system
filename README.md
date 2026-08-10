# Bastak Market Intelligence System — Phase 1 (Collector)

Early-warning radar for flour-mill projects, tenders, and news across your
target markets (Pakistan, Turkey, Africa, Middle East, Russia/CIS).

**Phase 1 scope (this folder):** read a curated source list, pull all RSS
feeds (including Google Alerts delivered as RSS), and store new items —
deduplicated — in a local SQLite database. No AI scoring, notifications, or
Excel export yet; those are Phase 2/3.

```
sources.yaml ──▶ collect.py ──▶ intel.db
 (you edit)      (RSS fetch)     (deduplicated store + run log)
```

## Files

| File              | Purpose                                                            |
|-------------------|--------------------------------------------------------------------|
| `sources.yaml`    | The source registry. **This is the file you edit** — one row per source. |
| `init_db.py`      | Creates `intel.db` and its schema. Safe to run repeatedly.         |
| `collect.py`      | Fetches enabled RSS sources, stores new items, writes a run log.   |
| `requirements.txt`| Python dependencies for Phase 1.                                   |
| `intel.db`        | SQLite database (created on first run). Two tables: `items`, `collection_log`. |

_Not built yet (later phases): `classify.py` (AI scoring), `notify.py` (Telegram), `export.py` (Excel)._

## 1. One-time setup

Requires **Python 3.10+**. Check with `python --version`.

Open **PowerShell** in this folder and run:

```powershell
# (recommended) create an isolated environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# install dependencies
pip install -r requirements.txt

# create the database
python init_db.py
```

If `Activate.ps1` is blocked by execution policy, either run this once:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, or just skip the venv
and `pip install` into your global Python.

## 2. Configure sources

`sources.yaml` ships with **5 verified working feeds enabled** — World-Grain
articles plus four Google News searches (Pakistan, Africa, global milling-plant
tenders, Turkey). These already pull real leads, so you can run immediately and
tune later.

**To adjust a Google News search:** edit the `?q=...` query in the URL
(URL-encoded). To cover a new market, copy an entry and change the query +
`country`.

**To add your own classic Google Alerts** (optional): go to
<https://www.google.com/alerts>, create an alert, set **Deliver to → RSS feed**,
paste the feed URL into a `google_alert` entry, and set `enabled: true`.

**To add any website:** copy an entry, set `name`, `url`, `type`, `language`,
`country`, `enabled: true`. Verify each RSS URL in a browser first — feeds move.
`html` / `tender` entries are stored but **not fetched** in Phase 1.

## 3. Run it

```powershell
python collect.py            # normal run
python collect.py --verbose  # also print each new item title
```

You'll see per-source counts (`N in feed, M new`) and a total.

### Check what's in the database

```powershell
# newest 10 items
python -c "import sqlite3;[print(r) for r in sqlite3.connect('intel.db').execute('SELECT collected_at,source_name,title FROM items ORDER BY id DESC LIMIT 10')]"

# health check — did each source produce items in the last run?
python -c "import sqlite3;[print(r) for r in sqlite3.connect('intel.db').execute('SELECT run_at,source_name,items_found,items_new,status FROM collection_log ORDER BY id DESC LIMIT 20')]"
```

Or open `intel.db` in **DB Browser for SQLite** (free GUI) to browse rows.

## 4. Schedule it — Windows Task Scheduler (daily 07:00)

The spec calls for a daily 07:00 run. Two ways to set it up.

### Option A — one command (PowerShell as Administrator)

Adjust the two paths if your Python or project location differs.
This example uses a venv; if you did **not** create one, replace the venv
python path with just `python` (or your full `python.exe` path).

```powershell
$proj   = "C:\Users\Icticaret7\Desktop\website data\Tracking_Project"
$python = "$proj\.venv\Scripts\python.exe"   # or: (Get-Command python).Source

$action  = New-ScheduledTaskAction -Execute $python -Argument "collect.py" -WorkingDirectory $proj
$trigger = New-ScheduledTaskTrigger -Daily -At 7:00am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun

Register-ScheduledTask -TaskName "BastakMarketIntel-Collect" `
  -Action $action -Trigger $trigger -Settings $settings `
  -Description "Daily flour-mill market-intelligence RSS collection"
```

`-StartWhenAvailable` makes it catch up if the PC was off at 07:00.
Test it immediately without waiting for tomorrow:

```powershell
Start-ScheduledTask -TaskName "BastakMarketIntel-Collect"
Get-ScheduledTaskInfo -TaskName "BastakMarketIntel-Collect"   # LastTaskResult 0 = success
```

Remove it later with:
`Unregister-ScheduledTask -TaskName "BastakMarketIntel-Collect" -Confirm:$false`

### Option B — the GUI

1. Open **Task Scheduler** → **Create Basic Task…**
2. Name: `BastakMarketIntel-Collect` → **Next**.
3. Trigger: **Daily**, start time **07:00** → **Next**.
4. Action: **Start a program** → **Next**.
5. **Program/script:** full path to python
   (e.g. `...\Tracking_Project\.venv\Scripts\python.exe`).
   **Add arguments:** `collect.py`.
   **Start in:** `C:\Users\Icticaret7\Desktop\website data\Tracking_Project`
   (this must be set, or `sources.yaml` / `intel.db` won't be found).
6. Finish. Then in the task's **Properties → General**, tick
   **Run whether user is logged on or not**, and in **Settings** enable
   **Run task as soon as possible after a scheduled start is missed**.

> **Note:** Task Scheduler only runs while the PC is on. If you need collection
> even when your PC is off, move it to a small VPS or GitHub Actions later
> (Phase 4 in the master doc).

## Troubleshooting

- **`ModuleNotFoundError: feedparser`** — dependencies not installed, or the
  scheduled task used a different Python than the one you `pip install`ed into.
  Point the task at your venv's `python.exe`.
- **A source shows `error` in `collection_log`** — the feed URL is wrong or the
  site is down. Open the URL in a browser; fix it in `sources.yaml`.
- **A source shows `0 in feed` for days** — likely a dead/changed feed. This is
  exactly the "scrapers break silently" check; replace the URL or the source.
- **Nothing new on later runs** — expected. Dedup means an item is stored once;
  `M new` will be 0 until the feeds publish something you haven't seen.

## What's next

- **Phase 1 remaining:** `export.py` → generate `leads.xlsx` (openpyxl, header
  fill `#32A337`, ALL sheet + per-country sheets) from `intel.db`.
- **Phase 2:** `classify.py` (Claude API scoring) + `notify.py` (Telegram alerts ≥ 7).
- **Phase 3:** structured tender scrapers (PPRA first) and change detection.

See `market-intelligence-system.md` for the full plan.
