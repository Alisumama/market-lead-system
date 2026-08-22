import 'dart:async';

import 'package:flutter/material.dart';

import '../data/lead_repository.dart';
import '../data/models/feed_source.dart';
import '../data/models/lead.dart';
import '../scoring/keyword_scorer.dart';
import '../services/notification_service.dart';
import '../services/pipeline.dart';
import '../services/settings_service.dart';

/// How the leads list is rendered.
enum LeadView { list, grid }

/// The single source of truth for the UI. Holds the current query/results,
/// runs the pipeline, owns the in-app refresh timer (the Task Scheduler
/// replacement), and exposes every data-editing action the user can take.
class AppState extends ChangeNotifier {
  final LeadRepository repo;
  final SettingsService settings;
  final NotificationService notifications;
  late Pipeline pipeline;

  AppState({
    required this.repo,
    required this.settings,
    required this.notifications,
  }) {
    pipeline = Pipeline(repo: repo);
  }

  // ---- observable state ----
  List<Lead> leads = [];
  LeadStats stats = const LeadStats();
  List<String> countries = [];
  List<String> sourceNames = [];
  List<FeedSource> sources = [];
  LeadQuery query = const LeadQuery();

  bool loading = true;
  bool refreshing = false;
  String? refreshStatus; // live progress string
  PipelineOutcome? lastOutcome;
  String? lastError;

  int freshDays = 90;
  bool autoRefreshHourly = true;
  DateTime? nextRefreshAt; // top of the next hour, when a scan will run
  ThemeMode themeMode = ThemeMode.system;
  LeadView leadView = LeadView.list;
  String? lastBatchAt; // UTC ISO; leads collected at/after this are "new"

  bool notifEnabled = false;
  bool notifAfterRefresh = true;
  bool notifOnlyNew = true;
  int notifMinScore = 0;

  bool lockOnBackground = true;
  int autoLockMinutes = 5;

  Timer? _timer;

  Future<void> init() async {
    freshDays = await settings.freshDays();
    autoRefreshHourly = await settings.autoRefreshHourly();
    notifEnabled = await settings.notifEnabled();
    notifAfterRefresh = await settings.notifAfterRefresh();
    notifOnlyNew = await settings.notifOnlyNew();
    notifMinScore = await settings.notifMinScore();
    lockOnBackground = await settings.lockOnBackground();
    autoLockMinutes = await settings.autoLockMinutes();
    leadView =
        (await settings.leadView()) == 'grid' ? LeadView.grid : LeadView.list;
    lastBatchAt = await settings.lastBatchAt();
    if (notifEnabled) unawaited(notifications.init());
    final dark = await settings.darkMode();
    themeMode = dark == null
        ? ThemeMode.system
        : (dark ? ThemeMode.dark : ThemeMode.light);
    query = query.copyWith(freshDays: freshDays);
    pipeline.scorer = KeywordScorer(await settings.scoringConfig());

    // Show what's already stored immediately… (never let a load error leave
    // the UI stuck on a spinner).
    try {
      await _reload();
    } catch (e) {
      lastError = e.toString();
    }
    loading = false;
    notifyListeners();

    // …and revalidate from the network in parallel (stale-while-revalidate).
    // The corner status chip reflects progress; data updates in place when done.
    unawaited(refresh());

    _scheduleHourly();
  }

  /// Fires the pipeline at the top of the next hour (:00), then reschedules for
  /// the following hour. Aligned to the wall clock, not to launch time. Only
  /// runs while the app is open.
  void _scheduleHourly() {
    _timer?.cancel();
    if (!autoRefreshHourly) {
      nextRefreshAt = null;
      return;
    }
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour)
        .add(const Duration(hours: 1));
    nextRefreshAt = next;
    _timer = Timer(next.difference(now), () async {
      if (!refreshing) await refresh(isAuto: true);
      _scheduleHourly();
    });
  }

  Future<void> _reload() async {
    leads = await repo.query(query);
    stats = await repo.stats(freshDays: freshDays);
    countries = await repo.countries();
    sourceNames = await repo.sourceNames();
    sources = await repo.allSources();
  }

  // ---- pipeline ----
  Future<void> refresh({bool isAuto = false}) async {
    if (refreshing) return;
    refreshing = true;
    lastError = null;
    refreshStatus = 'Starting…';
    notifyListeners();
    // Leads collected at/after this instant belong to this fetch batch.
    final batchStart = DateTime.now().toUtc().toIso8601String();
    try {
      final outcome = await pipeline.run(onProgress: (p) {
        refreshStatus =
            'Fetching ${p.sourceName}  (${p.index}/${p.total})';
        notifyListeners();
      });
      lastOutcome = outcome;
      refreshStatus = outcome.newLeads > 0
          ? '${outcome.newLeads} new lead(s)'
          : 'Up to date';
      if (outcome.newLeads > 0) {
        lastBatchAt = batchStart;
        await settings.setLastBatchAt(batchStart);
      }
      await _reload();
      if (isAuto) await _maybeNotify(outcome);
    } catch (e) {
      lastError = e.toString();
      refreshStatus = 'Refresh failed';
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// Fires a notification after an automatic (hourly) refresh, respecting the
  /// user's notification preferences.
  Future<void> _maybeNotify(PipelineOutcome outcome) async {
    if (!notifEnabled || !notifAfterRefresh) return;
    final count = outcome.newAtOrAbove(notifMinScore);
    if (notifOnlyNew && count == 0) return;
    final scope = notifMinScore > 0 ? ' (score ≥ $notifMinScore)' : '';
    final body = count > 0
        ? '$count new lead${count == 1 ? '' : 's'}$scope found.'
        : 'No new leads this time.';
    await notifications.show('Bastak Leads updated', body);
  }

  Future<void> sendTestNotification() =>
      notifications.show('Bastak Leads', 'Test notification — you\'re all set.');

  Future<void> rescoreAll() async {
    refreshing = true;
    refreshStatus = 'Re-scoring…';
    notifyListeners();
    final n = await pipeline.rescoreAll();
    refreshStatus = 'Re-scored $n lead(s)';
    await _reload();
    refreshing = false;
    notifyListeners();
  }

  // ---- query / filtering ----
  Future<void> applyQuery(LeadQuery q) async {
    query = q;
    leads = await repo.query(query);
    notifyListeners();
  }

  Future<void> setSearch(String s) => applyQuery(query.copyWith(search: s));
  Future<void> setMinScore(int v) => applyQuery(query.copyWith(minScore: v));
  Future<void> setSort(LeadSort s) => applyQuery(query.copyWith(sort: s));
  Future<void> setCountries(Set<String> c) =>
      applyQuery(query.copyWith(countries: c));
  Future<void> setSourceNames(Set<String> s) =>
      applyQuery(query.copyWith(sourceNames: s));
  Future<void> toggleFreshOnly(bool v) =>
      applyQuery(query.copyWith(freshOnly: v));
  Future<void> setDateRange(String from, String to) =>
      applyQuery(query.copyWith(dateFrom: from, dateTo: to));
  Future<void> toggleFavoritesOnly(bool v) =>
      applyQuery(query.copyWith(favoritesOnly: v));
  Future<void> setStatusFilter(Set<LeadStatus> s) =>
      applyQuery(query.copyWith(statuses: s));

  // ---- lead editing (full user control) ----
  Future<void> _saveLead(Lead lead) async {
    await repo.update(lead);
    final i = leads.indexWhere((l) => l.id == lead.id);
    if (i != -1) leads[i] = lead;
    stats = await repo.stats(freshDays: freshDays);
    notifyListeners();
  }

  /// True if the lead arrived in the most recent fetch batch and hasn't been
  /// opened yet — drives the "new" card highlight.
  bool isNew(Lead lead) =>
      !lead.seen &&
      lastBatchAt != null &&
      lead.collectedAt.compareTo(lastBatchAt!) >= 0;

  Future<void> markSeen(Lead lead) async {
    if (lead.seen || lead.id == null) return;
    await repo.markSeen(lead.id!);
    final i = leads.indexWhere((l) => l.id == lead.id);
    if (i != -1) leads[i] = leads[i].copyWith(seen: true);
    notifyListeners();
  }

  Future<void> toggleFavorite(Lead lead) =>
      _saveLead(lead.copyWith(favorite: !lead.favorite));

  Future<void> setStatus(Lead lead, LeadStatus status) =>
      _saveLead(lead.copyWith(status: status));

  Future<void> setNotes(Lead lead, String notes) =>
      _saveLead(lead.copyWith(notes: notes));

  /// User overrides the score; locks it so re-scoring won't clobber it.
  Future<void> overrideScore(Lead lead, int score) => _saveLead(
      lead.copyWith(score: score, scoreLocked: true, isRelevant: score >= 4));

  Future<void> unlockScore(Lead lead) async {
    final s = pipeline.scorer.score(title: lead.title, summary: lead.summary);
    await _saveLead(lead.copyWith(
      score: s.score,
      isRelevant: s.isRelevant,
      scoreLocked: false,
      scoreReason: s.reasonText,
    ));
  }

  Future<void> deleteLead(Lead lead) async {
    if (lead.id == null) return;
    await repo.delete(lead.id!);
    leads.removeWhere((l) => l.id == lead.id);
    stats = await repo.stats(freshDays: freshDays);
    notifyListeners();
  }

  Future<void> deleteMany(Iterable<Lead> items) async {
    final ids = items.where((l) => l.id != null).map((l) => l.id!).toList();
    await repo.deleteMany(ids);
    leads.removeWhere((l) => ids.contains(l.id));
    stats = await repo.stats(freshDays: freshDays);
    notifyListeners();
  }

  Future<void> setStatusMany(Iterable<Lead> items, LeadStatus status) async {
    final ids = items.where((l) => l.id != null).map((l) => l.id!).toList();
    await repo.updateStatusMany(ids, status);
    for (var i = 0; i < leads.length; i++) {
      if (ids.contains(leads[i].id)) {
        leads[i] = leads[i].copyWith(status: status);
      }
    }
    stats = await repo.stats(freshDays: freshDays);
    notifyListeners();
  }

  // ---- sources CRUD ----
  Future<void> reloadSources() async {
    sources = await repo.allSources();
    notifyListeners();
  }

  Future<void> saveSource(FeedSource s) async {
    if (s.id == null) {
      await repo.insertSource(s);
    } else {
      await repo.updateSource(s);
    }
    await reloadSources();
  }

  Future<void> toggleSource(FeedSource s, bool enabled) =>
      saveSource(s.copyWith(enabled: enabled));

  Future<void> deleteSource(FeedSource s) async {
    if (s.id != null) await repo.deleteSource(s.id!);
    await reloadSources();
  }

  /// Imports shared sources, skipping any that match an existing source.
  /// Matching is by a normalized URL (ignores scheme, host casing and a
  /// trailing slash) so http/https and "/feed" vs "/feed/" count as the same.
  /// Returns the number actually added.
  Future<int> importSources(List<FeedSource> incoming) async {
    final existing =
        (await repo.allSources()).map((s) => _normUrl(s.url)).toSet();
    var added = 0;
    for (final s in incoming) {
      final key = _normUrl(s.url);
      if (key.isEmpty || existing.contains(key)) continue;
      await repo.insertSource(s.copyWith(builtIn: false));
      existing.add(key);
      added++;
    }
    await reloadSources();
    // Newly imported feeds may bring new leads — fetch + rescore in the
    // background so the Leads list updates (the corner chip shows progress).
    if (added > 0) unawaited(refresh());
    return added;
  }

  static String _normUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return t.toLowerCase();
    var path = uri.path;
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    final q = uri.query;
    return '${uri.host.toLowerCase()}$path${q.isEmpty ? '' : '?$q'}';
  }

  // ---- settings ----
  Future<void> setAutoRefreshHourly(bool v) async {
    autoRefreshHourly = v;
    await settings.setAutoRefreshHourly(v);
    _scheduleHourly();
    notifyListeners();
  }

  Future<void> setFreshDays(int v) async {
    freshDays = v;
    await settings.setFreshDays(v);
    query = query.copyWith(freshDays: v);
    await _reload();
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool v) async {
    await settings.setBiometricEnabled(v);
    notifyListeners();
  }

  Future<void> setLockOnBackground(bool v) async {
    lockOnBackground = v;
    await settings.setLockOnBackground(v);
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int v) async {
    autoLockMinutes = v;
    await settings.setAutoLockMinutes(v);
    notifyListeners();
  }

  // ---- notifications ----
  /// Enables notifications, requesting OS permission first. Returns whether it
  /// ended up enabled (permission may be denied).
  Future<bool> setNotifEnabled(bool v) async {
    if (v) {
      final granted = await notifications.requestPermission();
      notifEnabled = granted;
      await settings.setNotifEnabled(granted);
      notifyListeners();
      return granted;
    }
    notifEnabled = false;
    await settings.setNotifEnabled(false);
    notifyListeners();
    return false;
  }

  Future<void> setNotifAfterRefresh(bool v) async {
    notifAfterRefresh = v;
    await settings.setNotifAfterRefresh(v);
    notifyListeners();
  }

  Future<void> setNotifOnlyNew(bool v) async {
    notifOnlyNew = v;
    await settings.setNotifOnlyNew(v);
    notifyListeners();
  }

  Future<void> setNotifMinScore(int v) async {
    notifMinScore = v;
    await settings.setNotifMinScore(v);
    notifyListeners();
  }

  // ---- data management ----
  Future<int> clearAllLeads() async {
    final n = await repo.deleteAll();
    await _reload();
    notifyListeners();
    return n;
  }

  Future<List<Lead>> allLeadsForExport() => repo.query(const LeadQuery());

  Future<void> setLeadView(LeadView v) async {
    leadView = v;
    await settings.setLeadView(v == LeadView.grid ? 'grid' : 'list');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await settings
        .setDarkMode(m == ThemeMode.system ? null : m == ThemeMode.dark);
    notifyListeners();
  }

  Future<void> saveScoringConfig(ScoringConfig c) async {
    await settings.saveScoringConfig(c);
    pipeline.scorer = KeywordScorer(c);
    notifyListeners();
  }

  Future<ScoringConfig> scoringConfig() => settings.scoringConfig();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
