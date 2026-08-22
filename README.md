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
