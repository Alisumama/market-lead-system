@echo off
REM ===========================================================================
REM  Bastak Market Intelligence System - hourly pipeline
REM  Runs: collect.py -> collect_email.py -> collect_worldbank_procurement.py
REM        -> classify.py --model haiku -> export.py -> build_dashboard.py
REM        -> deploy_dashboard.py
REM  All output is appended, with timestamps, to daily_run.log
REM  Intended to be launched by Windows Task Scheduler (see README).
REM
REM  ROBUSTNESS CONTRACT (do not break these when editing):
REM    1. NO step can abort the chain. Every step records its exit code and
REM       execution always continues, so build_dashboard.py and
REM       deploy_dashboard.py ALWAYS run -- a partial run still publishes.
REM    2. deploy_dashboard.py is ALWAYS the last pipeline step.
REM    3. Every run ends with a single HEARTBEAT line in daily_run.log so a
REM       silent freeze is visible at a glance.
REM ===========================================================================
setlocal enabledelayedexpansion

REM --- Always run from the folder this script lives in, so relative paths
REM     (sources.yaml, intel.db, .env, leads.xlsx) resolve correctly ---
cd /d "%~dp0"

set "LOG=daily_run.log"
set "LOCK=%~dp0run.lock"
set "STALE_MINUTES=15"

REM ===========================================================================
REM  SINGLE-INSTANCE GUARD
REM  Overlapping runs used to interrupt each other (classify got Ctrl+C when
REM  the next hourly run started). If a lockfile exists and is younger than
REM  STALE_MINUTES, a previous run is still going -> exit immediately. If the
REM  lock is older than that, the previous run almost certainly crashed or was
REM  killed (the lock is normally deleted on exit), so we override it.
REM  goto labels (not a parenthesized if-block) are used on purpose: the
REM  PowerShell age check contains parentheses, which corrupt cmd parsing when
REM  placed inside an ( ... ) block.
REM ===========================================================================
if not exist "%LOCK%" goto acquire_lock

set "LOCK_AGE=999"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "[int][math]::Floor(((Get-Date) - (Get-Item '%LOCK%').LastWriteTime).TotalMinutes)"`) do set "LOCK_AGE=%%A"
if !LOCK_AGE! GEQ %STALE_MINUTES% goto stale_lock

echo.>> "%LOG%"
echo [%date% %time%] SKIPPED - a previous run is still in progress ^(lock age !LOCK_AGE! min ^< %STALE_MINUTES% min^).>> "%LOG%"
echo HEARTBEAT %date% %time% ^| status=SKIPPED ^| reason=run-already-in-progress>> "%LOG%"
endlocal & exit /b 0

:stale_lock
echo.>> "%LOG%"
echo [%date% %time%] Stale lock ^(!LOCK_AGE! min ^>= %STALE_MINUTES% min^) - previous run likely crashed; overriding.>> "%LOG%"
del /f /q "%LOCK%"

:acquire_lock
REM --- Acquire the lock (deleted at the end of a normal run below) ---
echo %date% %time% pid-guard> "%LOCK%"

echo.>> "%LOG%"
echo ============================================================>> "%LOG%"
echo  Daily run started: %date% %time%>> "%LOG%"
echo ============================================================>> "%LOG%"

REM --- Step results. -1 means "never executed" so the heartbeat can tell that
REM     apart from "executed and returned non-zero". ---
set "RC_COLLECT=-1"
set "RC_EMAIL=-1"
set "RC_WBPROC=-1"
set "RC_CLASSIFY=-1"
set "RC_EXPORT=-1"
set "RC_BUILD=-1"
set "RC_DEPLOY=-1"

REM --- Activate the virtual environment if one exists; otherwise use the
REM     system Python on PATH ---
if exist ".venv\Scripts\activate.bat" (
    call ".venv\Scripts\activate.bat"
    echo [venv activated: .venv]>> "%LOG%"
) else (
    echo [no venv found - using system python]>> "%LOG%"
)

echo.>> "%LOG%"
echo --- collect.py  (%time%) --->> "%LOG%"
python collect.py >> "%LOG%" 2>&1
set "RC_COLLECT=!errorlevel!"
echo [collect.py exit code: !RC_COLLECT!]>> "%LOG%"

echo.>> "%LOG%"
echo --- collect_email.py  (%time%) --->> "%LOG%"
python collect_email.py >> "%LOG%" 2>&1
set "RC_EMAIL=!errorlevel!"
echo [collect_email.py exit code: !RC_EMAIL!]>> "%LOG%"

REM --- collect_worldbank.py (WDS documents) was RETIRED on 2026-08-05: the WDS
REM     archive has no recent milling content (newest milling-specific match is
REM     from 2012), so it only produced volume via broad terms like "food
REM     security" that flooded classify and caused wrong country tags. See the
REM     docstring in collect_worldbank.py. Procurement notices below replace it.

echo.>> "%LOG%"
echo --- collect_worldbank_procurement.py  (%time%) --->> "%LOG%"
python collect_worldbank_procurement.py >> "%LOG%" 2>&1
set "RC_WBPROC=!errorlevel!"
echo [collect_worldbank_procurement.py exit code: !RC_WBPROC!]>> "%LOG%"

REM --- Classify only a capped slice of the NEWEST unclassified items so this
REM     step always finishes quickly instead of grinding through the whole
REM     backlog. Leftover items are picked up on the next run.
REM     Exit codes: 0 = classified (or nothing to do), 2 = SKIPPED because the
REM     local claude CLI is unavailable / not logged in, 1 = unexpected error.
REM     All three are non-fatal here: the chain continues either way.
echo.>> "%LOG%"
echo --- classify.py --model haiku --limit 50  (%time%) --->> "%LOG%"
python classify.py --model haiku --limit 50 >> "%LOG%" 2>&1
set "RC_CLASSIFY=!errorlevel!"
echo [classify.py exit code: !RC_CLASSIFY!  (0=ok, 2=skipped-cli-unavailable, 1=error)]>> "%LOG%"

REM --- export + build ALWAYS run next, even if collect or classify errored,
REM     was capped, or was interrupted: they simply use whatever is in
REM     intel.db so far, so the dashboard always rebuilds with the latest
REM     available data.
echo.>> "%LOG%"
echo --- export.py  (%time%) --->> "%LOG%"
python export.py >> "%LOG%" 2>&1
set "RC_EXPORT=!errorlevel!"
echo [export.py exit code: !RC_EXPORT!]>> "%LOG%"

echo.>> "%LOG%"
echo --- build_dashboard.py  (%time%) --->> "%LOG%"
python build_dashboard.py >> "%LOG%" 2>&1
set "RC_BUILD=!errorlevel!"
echo [build_dashboard.py exit code: !RC_BUILD!]>> "%LOG%"

REM --- ALWAYS THE LAST PIPELINE STEP. Publishes dashboard.html to the private
REM     Supabase bucket the auth gate serves from (bucket name comes from
REM     SUPABASE_DASHBOARD_BUCKET in .env -- currently 'dashboards'). If this
REM     fails, the previously published version stays live untouched: it does
REM     not roll back or corrupt anything, it just means this build wasn't
REM     picked up. See web/SETUP.md.
echo.>> "%LOG%"
echo --- deploy_dashboard.py  (%time%) --->> "%LOG%"
python deploy_dashboard.py >> "%LOG%" 2>&1
set "RC_DEPLOY=!errorlevel!"
echo [deploy_dashboard.py exit code: !RC_DEPLOY!]>> "%LOG%"

REM --- Heartbeat: one machine-readable line summarising the whole run,
REM     including the fresh-lead count actually published and an independent
REM     check that the object in the bucket really was updated. Never fatal.
echo.>> "%LOG%"
python pipeline_health.py --collect !RC_COLLECT! --email !RC_EMAIL! --wbproc !RC_WBPROC! --classify !RC_CLASSIFY! --export !RC_EXPORT! --build !RC_BUILD! --deploy !RC_DEPLOY! >> "%LOG%" 2>&1

REM --- Release the single-instance lock so the next scheduled run can start ---
del /f /q "%LOCK%" 2>nul
echo [lock released]>> "%LOG%"

echo.>> "%LOG%"
echo  Daily run finished: %date% %time%>> "%LOG%"
echo ============================================================>> "%LOG%"

endlocal
