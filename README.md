# Bastak Leads — cross-platform lead radar

A single Flutter app (Windows · macOS · Android) that finds sales leads for
grain / flour / milling projects and tenders. It replaces the old Python +
Supabase + Vercel + Windows-Task-Scheduler stack with one self-contained,
**offline, local-first** app:

| Old system | Now |
|---|---|
| Vercel-hosted dashboard | The app **is** the dashboard |
| Supabase/Postgres + invite login | **Local device auth** (biometric + PIN), local SQLite |
| Windows Task Scheduler | **In-app auto-refresh** timer + refresh-on-launch + manual |
| Claude CLI / API classifier | **Offline keyword scorer** (tunable, explainable) |
| Gmail IMAP collector | Dropped (RSS + World Bank are keyless & reliable) |

## What it does

1. **Collects** from RSS/Atom feeds, Google News searches, and the World Bank
   procurement-notices API (real tenders — the highest-quality leads).
2. **Scores** each item 0–10 with a transparent keyword engine (facility +
   intent + capacity/budget signals, minus generic-news penalties). Every score
   shows *why*.
3. **Stores** everything in a local SQLite DB, deduplicated by URL hash.
4. **Lets you drive the data**: filter/search/sort, per-country slicing, edit a
   score (locks it), set pipeline status (New→Won/Lost), star, add notes,
   delete, and export to CSV.

## Architecture

```
lib/
├── data/            models, SQLite database, repository, default source registry
├── collectors/      RssCollector, WorldBankCollector, date parsing
├── scoring/         KeywordScorer (the offline classifier)
├── services/        pipeline, settings, auth, CSV export
├── state/           AppState (Provider) + in-app refresh timer
├── theme/           Material 3 theme (brand green #32A337)
└── ui/              auth, home (leads), sources, settings
```

## Run it

```sh
flutter pub get

flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run -d android    # Android device/emulator
```

Build releases:

```sh
flutter build macos       # build/macos/Build/Products/Release/
flutter build windows     # build/windows/x64/runner/Release/
flutter build apk         # build/app/outputs/flutter-apk/app-release.apk
```

### Shipping the Windows build

`build/windows/x64/runner/Release/` is a **self-contained, portable folder** —
copy the whole folder to any Windows 10/11 x64 machine and run
`bastak_leads.exe`. No installer, no runtime prerequisites.

It contains the executable, `data/` (Dart AOT image, ICU data, Flutter assets),
the Flutter engine and plugin DLLs, and the Visual C++ runtime
(`MSVCP140.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll` + MSVCP satellites).
Those CRT DLLs are **not** part of a stock Flutter build — a clean Windows
install has no VC++ Redistributable, so the app would fail to start with
"VCRUNTIME140.dll was not found". They get copied in by the
`InstallRequiredSystemLibraries` block at the bottom of
`windows/CMakeLists.txt`, so every `flutter build windows` includes them.

Everything else the binaries import is either in that folder or in-box on
Windows 10+ (`kernel32`, `ole32`, `dwmapi`, `d3d9`/`dxgi`, the UCRT
`api-ms-win-crt-*` API sets, …), so nothing else needs shipping. Zip it:

```powershell
Compress-Archive -Path build\windows\x64\runner\Release\* `
  -DestinationPath bastak_leads-windows-x64.zip
```

> `dartjni.dll` in the output imports `jvm.dll`, which does not exist on
> Windows. It is an unused native asset pulled in by `path_provider_android`
> and is never loaded on desktop — harmless, and safe to delete if you want a
> smaller drop.

### Windows installer

For a real setup wizard instead of a zip, build the Inno Setup installer:

```powershell
winget install JRSoftware.InnoSetup          # one time
powershell -ExecutionPolicy Bypass -File tool\build_windows_installer.ps1
# -> build\windows\installer\bastak_leads-<version>-windows-x64-setup.exe
```

The script runs `flutter build windows --release`, reads the version from
`pubspec.yaml` so nothing drifts, refuses to package a bundle that is missing
the VC++ runtime DLLs, and compiles `windows\installer\bastak_leads.iss`.
Pass `-SkipBuild` to repackage an existing build.

The wizard is branded from the assets in `assets/`: `tool\make_installer_branding.ps1`
composites the white knockout logo onto a brand-green gradient for the full-height
panel on the Welcome and Finish pages, and the app icon onto white for the header
badge on the inner pages. Both are emitted at several sizes so Inno can pick one
matching the user's DPI. The bitmaps are generated into `build\` on every build
rather than committed, so a brand refresh only means replacing the PNGs.

Note that `WizardStyle=modern` **disables the Welcome page by default**, which is
the only page showing the large panel — `DisableWelcomePage=no` turns it back on.

The installer lets the user pick **"just me"** (installs to
`%LOCALAPPDATA%\Programs\Bastak Leads`, no admin needed) or **"all users"**
(`Program Files`, prompts for admin), creates Start Menu and optional desktop
shortcuts, and registers a proper uninstaller in Add/Remove Programs. Upgrades
replace the previous version in place — the `AppId` GUID in the `.iss` must
never change, or upgrades would install alongside the old copy instead.

Uninstalling **keeps your leads by default**; it asks whether to also delete
`%APPDATA%\com.bastak\Bastak Leads`, defaulting to No. That folder holds the
SQLite database, the `flutter_secure_storage` blob and the image cache, so
saying Yes clears the saved PIN along with the leads.

That path is `CompanyName\ProductName` from `windows\runner\Runner.rc`, which is
what `path_provider` uses. The build script reads it from there and passes it to
the installer rather than the `.iss` hardcoding it — when `ProductName` changed
from `bastak_leads` to `Bastak Leads`, a hardcoded copy silently went stale and
left the uninstaller pointing at a folder that no longer existed.

Silent install/uninstall, for pushing it out to several machines:

```powershell
bastak_leads-2.1.1-windows-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER
"%LOCALAPPDATA%\Programs\Bastak Leads\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

A silent uninstall never deletes user data. (This relies on the script using
`SuppressibleMsgBox` rather than `MsgBox` — a plain `MsgBox` is not suppressed
and wiped the database during unattended uninstalls.)

The installer is **not code-signed**, so SmartScreen will show a
"Windows protected your PC" warning on first run; users click *More info →
Run anyway*. Signing it with an EV/OV certificate is the only way to remove
that.

## Verify the data path (no GUI)

```sh
dart run tool/smoke_test.dart   # fetches live feeds, scores, prints top leads
flutter test                    # scorer unit tests
```

## Notes / tradeoffs

- **Login loads stored data instantly** — no network wait. New leads are
  fetched only when you hit *Refresh now* (or pull-to-refresh), or by the
  **hourly auto-refresh at the top of each hour (:00)** while the app is open
  (toggle in Settings). Nothing runs when the app is closed.
- The keyword scorer is fully editable in **Settings → Scoring keywords**, with
  a live "Try it" preview. After changing vocabulary, use **Re-score all**.
- Data lives in the app's support directory (`bastak_leads.db`). Nothing leaves
  the device.
