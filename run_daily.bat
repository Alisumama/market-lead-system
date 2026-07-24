@echo off
REM ===========================================================================
REM  Bastak Market Intelligence System - daily pipeline
REM  Runs: collect.py -> collect_email.py -> collect_worldbank.py
REM        -> collect_worldbank_procurement.py -> classify.py --model haiku
REM        -> export.py -> build_dashboard.py
REM  All output is appended, with timestamps, to daily_run.log
REM  Intended to be launched by Windows Task Scheduler (see README).
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

echo.>> "%LOG%"
echo --- collect_email.py  (%time%) --->> "%LOG%"
python collect_email.py >> "%LOG%" 2>&1

echo.>> "%LOG%"
echo --- collect_worldbank.py  (%time%) --->> "%LOG%"
python collect_worldbank.py >> "%LOG%" 2>&1

echo.>> "%LOG%"
echo --- collect_worldbank_procurement.py  (%time%) --->> "%LOG%"
python collect_worldbank_procurement.py >> "%LOG%" 2>&1

REM --- Classify only a capped slice of the NEWEST unclassified items so this
REM     step always finishes quickly (~2 min) instead of grinding through the
REM     whole backlog and getting killed. Leftover items are picked up on the
REM     next daily run. Raise --limit or run "python classify.py --model haiku"
REM     manually (no cap) to burn down the backlog faster.
echo.>> "%LOG%"
echo --- classify.py --model haiku --limit 50  (%time%) --->> "%LOG%"
python classify.py --model haiku --limit 50 >> "%LOG%" 2>&1
echo [classify.py exit code: %errorlevel%]>> "%LOG%"

REM --- export + build ALWAYS run next, even if classify was capped, errored, or
REM     was interrupted: they simply use whatever is classified in intel.db so
REM     far, so the dashboard always rebuilds with the latest available data.
echo.>> "%LOG%"
echo --- export.py  (%time%) --->> "%LOG%"
python export.py >> "%LOG%" 2>&1
echo [export.py exit code: %errorlevel%]>> "%LOG%"

echo.>> "%LOG%"
echo --- build_dashboard.py  (%time%) --->> "%LOG%"
python build_dashboard.py >> "%LOG%" 2>&1
echo [build_dashboard.py exit code: %errorlevel%]>> "%LOG%"

REM --- Release the single-instance lock so the next scheduled run can start ---
del /f /q "%LOCK%" 2>nul
echo [lock released]>> "%LOG%"

echo.>> "%LOG%"
echo  Daily run finished: %date% %time%>> "%LOG%"
echo ============================================================>> "%LOG%"

endlocal
