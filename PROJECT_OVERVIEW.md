# Bastak Leads — Project Overview

> A hand-off document for any developer (human or AI) picking up this codebase.
> It explains what the app is, how it's architected, where everything lives, and
> the non-obvious conventions you must follow.

---

## 1. What this is

**Bastak Leads** is a cross-platform **Flutter desktop/mobile app** (Windows,
macOS, Android) that acts as a **local-first sales-lead radar** for
**Bastak Instruments** — a company selling grain/flour/milling equipment and
lab instruments (falling number, gluten index, farinograph, NIR analyzers, etc.).

It continuously collects news/tender/procurement items from RSS feeds, Google
News alerts, and the World Bank projects API, **scores** each item with a
transparent keyword engine (no AI/LLM), and surfaces the highest-quality
potential leads. The user has **complete control** over the data and the rules.

### Hard product constraints (do not violate)
- **No cloud, no server, no database service.** Everything runs on the user's
  machine. No Vercel, no Postgres, no Supabase. The app itself is the dashboard.
- **No OS scheduler dependency** for the core loop (the app owns its own timer);
  optional background refresh uses per-platform mechanisms (see §7).
- **Keyword scoring, not AI.** Scoring is deterministic, offline, explainable,
  and fully user-configurable.
- **All data stays on device.** No telemetry, no secrets committed.

### This is a rewrite
It replaces an older Python pipeline (`market-lead-system/`, Vercel + Postgres +
Windows Task Scheduler). The SQLite schema deliberately mirrors the old
`source_type` values so a legacy `intel.db` could in principle be imported.

---

## 2. Tech stack

- **Flutter 3.41.4 / Dart 3.11.1**, Material 3.
- **State management:** `provider` (`ChangeNotifier`) — single `AppState` is the
  source of truth.
- **Local DB:** `sqflite` (Android/macOS native) + `sqflite_common_ffi`
  (Windows/Linux). Schema migrations via `onCreate`/`onUpgrade`.
- **Auth:** `local_auth` (biometric) + PIN (`crypto` sha256+salt) stored via
  `flutter_secure_storage`, with a **file fallback** (`SecureKv`) for unsigned
  macOS.
- **Charts:** `fl_chart` + custom painters.
- **Export:** `csv` (hand-rolled), `excel` (decorated XLSX), `pdf` (branded).
- **Files:** `file_picker` v12 (native save/open dialogs), `path_provider`.
- **Notifications:** `flutter_local_notifications` (mobile/macOS/Linux) +
  `local_notifier` (Windows).
- **Networking:** `http` + `xml` (RSS parsing).
- **Other:** `cached_network_image`, `flutter_svg`, `share_plus`,
  `url_launcher`, `package_info_plus`, `workmanager` (Android background).

Current version: **`2.1.4+9`** (see §9 for the versioning rule).
Active branch: **`v2-flutter-app`**. Remote:
`github.com/Alisumama/market-lead-system` (origin).

> ⚠️ The git repo root is the **`bastak_leads/` subdirectory**, not the parent
> `SUMAMA/` folder.

---

## 3. Directory map (`lib/`)

```
lib/
├── main.dart                     # Entry point, AuthGate, headless mode, auto-lock
│
├── collectors/                   # Fetch raw items from the network
│   ├── collector.dart            # Collector interface + CollectResult/RawItem
│   ├── rss_collector.dart        # RSS/Atom + Google News feeds
│   ├── worldbank_collector.dart  # World Bank projects API (tenders)
│   ├── url_unwrap.dart           # Unwraps Google News redirect URLs
│   └── date_utils.dart           # Publish-date normalization → yyyy-MM-dd
│
├── data/
│   ├── app_database.dart         # SQLite open + schema + migrations + seeding
│   ├── default_sources.dart      # Built-in feed registry seeded on first run
│   ├── lead_repository.dart      # LeadQuery, CRUD, dedup, stats, countries
│   ├── reports_repository.dart   # Aggregations for the Reports dashboard
│   └── models/
│       ├── lead.dart             # Lead + SourceKind + LeadStatus enums
│       └── feed_source.dart      # FeedSource + SourceKind mapping
│
├── scoring/
│   └── keyword_scorer.dart       # ScoringConfig, KeywordScorer, RejectReason,
│                                 #   RuleProfile — the whole rules engine
│
├── services/
│   ├── pipeline.dart             # Orchestrates collect→score→reject→store
│   ├── settings_service.dart     # All persisted prefs (via SecureKv)
│   ├── secure_kv.dart            # Secure storage w/ file fallback (macOS)
│   ├── auth_service.dart         # PIN + biometric
│   ├── notification_service.dart # Cross-platform notifications
│   ├── background_service.dart   # Registers OS background refresh
│   ├── headless_refresh.dart     # `--headless` one-shot refresh + exit
│   ├── export_service.dart       # Leads/sources/rules export + import
│   ├── exporter.dart             # CSV/XLSX/PDF byte builders
│   ├── file_service.dart         # Native save/open (desktop) + mobile storage
│   └── share_helper.dart         # Share lead(s) text
│
├── state/
│   └── app_state.dart            # THE central ChangeNotifier
│
├── theme/
│   └── app_theme.dart            # Material 3 theme, brand colors
│
├── ui/
│   ├── splash_screen.dart
│   ├── auth/lock_screen.dart
│   ├── home/
│   │   ├── home_shell.dart        # Adaptive nav (rail/bottom bar), 5 tabs
│   │   ├── leads_page.dart        # Leads list/grid, filters, bulk actions
│   │   └── lead_detail.dart       # Single lead detail + score edit
│   ├── sources/
│   │   ├── sources_page.dart      # Feed registry, filters, import/export
│   │   └── source_editor.dart
│   ├── rules/
│   │   └── rules_page.dart        # THE Rules module (scoring + filters)
│   ├── reports/
│   │   └── reports_page.dart      # Premium dashboard w/ drill-downs
│   ├── settings/
│   │   └── settings_page.dart
│   └── widgets/                   # Shared: brand_logo, score_badge,
│                                  #   multi_select_sheet, format_picker, etc.
└── util/
    └── text.dart                 # cleanHtmlText, etc.
```

---

## 4. Data flow (the core loop)

```
FeedSource(s)  ──►  Collector.fetch()  ──►  RawItem[]        (network, parallel)
                                             │
                                             ▼
                          KeywordScorer.score()   → ScoreResult (0..10, company,
                                             │                     country, type)
                                             ▼
                          KeywordScorer.reject()  → RejectReason?  (accept gate)
                                             │
                              null? ── yes ─►  LeadRepository.insertIfNew()  (dedup)
                                │ no
                                └──►  counted in rejectedByReason (dropped)
                                             │
                                             ▼
                                    AppState._reload()  ──►  UI rebuilds
```

- **`Pipeline.run()`** (`services/pipeline.dart`): Phase 1 fetches every enabled
  source concurrently (bounded pool, `_fetchConcurrency = 6`). Phase 2 scores +
  applies the reject gate + stores **serially** (SQLite writes are serial; dedup
  stays race-free). Returns a `PipelineOutcome` (counts, `newScores`,
  `rejected`, `rejectedByReason`).
- **Dedup** is two-layer: `url_hash` (sha256 of URL) UNIQUE + a normalized
  `dedup_key` (title with trailing " - Publisher" stripped) to catch the same
  story from different feeds.

---

## 5. The Rules engine (`scoring/keyword_scorer.dart`) — most important module

This is the heart of "data quality." It has four public types:

### `ScoringConfig` (serializable, import/export/share-able)
- **Vocabulary:** `facilityTerms`, `intentTerms`, `negativeTerms`,
  `requiredKeywords` (topic gate), `blockedKeywords`.
- **Weights:** `facilityWeight`, `intentWeight`, `capacityWeight`,
  `budgetWeight`, `companyWeight`, `negativeWeight`, `recencyBoost`+`recencyDays`,
  `tenderBoost`, `relevanceCutoff`.
- **Acceptance/rejection filters:** `requireFacility`, `minScoreToStore`,
  `maxAgeDays`, `rejectUndated`, `allowedCountries`, `blockedCountries`,
  `allowedLanguages`, `allowedSourceKinds`, `minCapacityTpd`, `minBudgetUsd`.
- Has `copyWith`, `toJson`, `fromJson` (tolerant of missing keys / legacy files).

### `KeywordScorer`
- **`score({title, summary, publishedDate, sourceKind})` → `ScoreResult`**:
  facility base + intent + capacity/budget regex + company + tender/recency
  boosts − negative penalty, clamped 0..10.
- **`reject({..., score})` → `RejectReason?`** (null = accept): checks blocked/
  required keywords, requireFacility, undated, maxAge, language, source kind,
  country allow/block, min capacity, min budget, min score — **in that order**.
- **Whole-word matching** (`_containsWord`, Unicode-aware via `\p{L}\p{N}`):
  the scorer matches terms as whole words/phrases, NOT substrings — so `mill`
  ≠ "million", `invest` ≠ "investigation". **This is critical**; naive
  `.contains()` was a false-positive bug that was fixed.
- **Capacity/budget extraction:** `_maxCapacity` (tons/day) and `_maxBudget`
  (USD-equivalent; requires explicit currency so "20 million **tons**" is not
  read as money). The min-capacity/min-budget gates only drop items that
  **state** a figure below the bar — figure-less items are kept.

### `RejectReason` enum
`noFacility, missingRequiredKeyword, blockedKeyword, tooOld, undated,
countryNotAllowed, countryBlocked, languageNotAllowed, sourceNotAllowed,
belowMinScore, belowMinCapacity, belowMinBudget` — each has a `.label`.

### `RuleProfile`
`{name, config}` — a named, saveable rule set (Strict / Wide net / Tenders only).
Serializable; persisted as a list in settings.

### The Rules UI (`ui/rules/rules_page.dart`)
5th nav tab. Sections: **Profiles** card (save/load/delete named sets), **Try it**
card (live score + accept/reject preview with reason), **Data quality** card
(last-run reject breakdown + a non-destructive **dry-run** "test rules on current
leads"), **Scoring weights** sliders, five **keyword sections**, **Acceptance
filters** (switches, min-score slider, max-age dropdown, capacity/budget
dropdowns, country allow/block + language + source multi-selects). App-bar menu:
import/export/reset rules. FAB: **Re-score all**. Saving updates the live
pipeline scorer immediately.

---

## 6. Persistence

### SQLite (`data/app_database.dart`)
- `leads` table (columns: `url_hash UNIQUE`, `url`, `title`, `summary`,
  `published`, `published_date`, `source_name`, `source_type`, `language`,
  `country`, `collected_at`, `score`, `is_relevant`, `company`, `project_type`,
  `detected_country`, `score_reason`, `score_locked`, `status`, `favorite`,
  `notes`, `dedup_key`, `image_url`, `seen`). Indexed on score, pubdate, country,
  status, dedup_key.
- `sources` table (name, url, kind, language, country, enabled, built_in,
  last_status/error/found/new/run_at).
- **Migrations:** bump `_dbVersion` and add a step to the `_migrations` map. Steps
  so far added `dedup_key`, `image_url`, `seen`.

### Settings (`services/settings_service.dart` via `SecureKv`)
Keys include: auto-refresh, fresh days, lead view, last batch, background enabled,
dark mode, notification prefs, **`scoring_config_v2`** (the active rules blob),
**`reject_stats_v1`** (last-run breakdown), **`rule_profiles_v1`**, PIN hash,
biometric, lock-on-background, auto-lock minutes.

> ⚠️ **SQLite DQS gotcha:** the FFI-bundled SQLite (Windows/Linux) has
> `SQLITE_DQS=0` — double-quoted string literals are disabled. **Always use
> single quotes `''` for string literals in raw SQL** (e.g. `ORDER BY ... ''`).
> A `""` empty-string literal silently broke the Windows leads list once.

---

## 7. Refresh & background behavior

- **On unlock:** load stored data instantly, then revalidate from the network in
  parallel (stale-while-revalidate). A corner status chip shows progress.
- **Auto-refresh:** hourly at `:00` (wall-clock aligned) while the app is open,
  via an in-app `Timer` in `AppState._scheduleHourly()`.
- **Background refresh (app closed):** `--headless` app mode
  (`_HeadlessRunner` → `runHeadlessRefresh` → `exit(0)`), triggered by:
  - **macOS:** launchd LaunchAgent (`StartInterval 3600`)
  - **Windows:** `schtasks`
  - **Android:** `workmanager`
- **Locked refresh:** `AuthGate.initState` calls `AppState.init()` at launch
  independent of unlock, so refresh + notifications fire even while locked.
- **Notifications:** fired after an **auto** refresh only (respecting prefs:
  enabled, only-new, min-score).

---

## 8. Auth & platform notes

- **PIN + biometric** unlock. `SecureKv` probes **write+delete** (not just read)
  to decide if OS secure storage works, falling back to a file on unsigned macOS
  (Keychain error `-34018 errSecMissingEntitlement` — the machine has no signing
  identity).
- **macOS entitlements:** `network.client`,
  `files.user-selected.read-write`. **Not** keychain-access-groups (needs a
  signing cert the machine lacks).
- **macOS keyboard bug:** the merged UI/platform thread broke text input →
  disabled via `Info.plist` `FLTEnableMergedPlatformUIThread = false`.
- **Auto-lock:** `lockOnBackground` is **mobile-only** (macOS reports
  hidden/inactive on focus loss, which caused spurious logouts).
- **App name** is "Bastak Leads" everywhere (macOS `PRODUCT_NAME` in
  AppInfo.xcconfig, Windows product name, icons regenerated full-bleed).
- **Export on desktop** uses a native save dialog (sandbox blocks silent
  Downloads writes); mobile uses the storage framework via `FileService`.

### Dependency pin to remember
`xml` is pinned to **^6.5.0** (not ^7) because `pdf` + `excel` both need xml ^6;
syncfusion was dropped for this reason. RSS parsing uses stable xml APIs.

---

## 9. Conventions you MUST follow

### Versioning (automated)
- **Every commit** → the `.githooks/pre-commit` hook bumps only the **build**
  number (`+N`). `core.hooksPath` is set to `.githooks`.
- **Every push** → run **`sh tool/push.sh`** (NOT a bare `git push`). It bumps
  the **version patch** (X.Y.Z→X.Y.Z+1), commits "Release: bump version" (hook
  bumps build again), then pushes.
- Only commit/push **when the user explicitly asks.**
- If on the default branch, branch first. (Work happens on `v2-flutter-app`.)

### Commit message trailers
End every commit message with these two lines (session id varies per session):
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_<id>
```

### graphify knowledge graph
There is a `graphify-out/` knowledge graph at the repo parent. For codebase
questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`,
`graphify explain "<concept>"` over raw grep. **After modifying code, run
`graphify update .`** (AST-only, no API cost).

### General
- Match surrounding code style (comment density, naming, idiom).
- Keep everything local — never add cloud/network persistence or telemetry.
- No secrets in the repo (the Flutter app has none).

---

## 10. Build / run / test

```bash
cd bastak_leads

flutter pub get
flutter analyze                       # must be clean
flutter test                          # full suite (see test/ below)

flutter run -d macos                  # or: -d windows, -d <android-device>
flutter build macos --debug           # artifact: build/macos/.../Bastak Leads.app

# Headless one-shot refresh (used by background schedulers):
# the app is launched with the --headless argument → refresh → exit(0)
```

### Tests (`test/`)
- `scorer_rules_test.dart` — whole-word matching, capacity/budget gates, blocked
  countries, config + profile JSON round-trips (the Rules engine).
- `dedup_unwrap_test.dart` — dedup key + Google News URL unwrapping.
- `query_sqlite_test.dart` — raw SQL / strict-SQLite (DQS) regression.
- `exporter_test.dart` — CSV/XLSX byte output.
- `brand_logo_test.dart`, `widget_test.dart`.

---

## 11. Feature inventory (what already exists)

- **Leads:** list + grid views, cached featured images, filters (min/max score,
  country, source name, project type, status multi-select, favorites, fresh-only,
  **date range**), search (title/URL), sort, bulk select + actions, share,
  new-lead highlight + seen state.
- **Sources:** built-in + user feeds, enable/disable, filters (type, country),
  search (name, URL), add/edit, **import/export** (JSON/CSV) with dedup by
  normalized URL, auto-reload leads after import.
- **Rules:** full module described in §5.
- **Reports:** premium Material-3 dashboard (bar/donut/line charts + custom
  painters), stat cards are **clickable → drill into filtered leads**
  (`AppState.showLeadsFiltered` + `requestTab`).
- **Settings:** notifications (incl. after-refresh), auto-refresh toggle,
  background refresh toggle, theme, auto-lock, PIN/biometric, about dialog with
  dynamic version+build.
- **Export everywhere:** CSV, decorated XLSX, branded PDF for leads and sources.

### Known minor gaps / possible next work
- Company-detection regex can still over-match some names.
- Deferred Rules ideas: per-source tender boost (not only World Bank), weighted
  `term:weight` vocabulary, per-section reset, richer import validation.
- Android/Windows background paths less run-verified than macOS.

---

## 12. Quick orientation for a new agent

1. Read `lib/state/app_state.dart` first — it wires everything (repo, pipeline,
   settings, notifications, background) and exposes every UI action.
2. Then `lib/services/pipeline.dart` and `lib/scoring/keyword_scorer.dart` for
   the collect→score→reject→store core.
3. Then the page you're changing under `lib/ui/`.
4. Respect §6 (single-quote SQL), §9 (versioning + commit trailers + graphify).
5. `flutter analyze` + `flutter test` before proposing a commit; only
   commit/push when explicitly asked, using `sh tool/push.sh` to push.
```
```
