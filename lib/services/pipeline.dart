import 'dart:math';

import '../collectors/collector.dart';
import '../collectors/rss_collector.dart';
import '../collectors/worldbank_collector.dart';
import '../data/lead_repository.dart';
import '../data/models/feed_source.dart';
import '../scoring/keyword_scorer.dart';

class PipelineProgress {
  final String sourceName;
  final int index;
  final int total;
  final int newItems;
  const PipelineProgress(
      this.sourceName, this.index, this.total, this.newItems);
}

class PipelineOutcome {
  final int sourcesRun;
  final int sourcesFailed;
  final int newLeads;
  final int scanned;
  final int rejected; // items dropped by the acceptance rules
  final Map<RejectReason, int> rejectedByReason; // breakdown of [rejected]
  final List<int> newScores; // scores of the newly-inserted leads
  final DateTime finishedAt;
  const PipelineOutcome({
    required this.sourcesRun,
    required this.sourcesFailed,
    required this.newLeads,
    required this.scanned,
    this.rejected = 0,
    this.rejectedByReason = const {},
    required this.newScores,
    required this.finishedAt,
  });

  int newAtOrAbove(int minScore) =>
      minScore <= 0 ? newLeads : newScores.where((s) => s >= minScore).length;
}

/// Result of testing the current (possibly unsaved) rules against the leads
/// already in the database — a preview of what tightening the rules would drop.
class DryRunResult {
  final int total;
  final int kept;
  final int dropped;
  final Map<RejectReason, int> byReason;
  const DryRunResult({
    required this.total,
    required this.kept,
    required this.dropped,
    required this.byReason,
  });
}

/// Orchestrates collect -> score -> store for every enabled source.
/// Pure-Dart replacement for the whole run_daily.bat chain (minus deploy —
/// there is no server; the app itself is the dashboard).
class Pipeline {
  final LeadRepository repo;
  KeywordScorer scorer;
  final List<Collector> _collectors;

  Pipeline({
    required this.repo,
    KeywordScorer? scorer,
    List<Collector>? collectors,
  })  : scorer = scorer ?? const KeywordScorer(),
        _collectors = collectors ??
            [RssCollector(), WorldBankCollector()];

  /// How many sources to fetch at once. Bounded so we're fast without
  /// hammering (and risking rate-limits from) Google News / World Bank.
  static const _fetchConcurrency = 6;

  Future<PipelineOutcome> run({
    void Function(PipelineProgress)? onProgress,
  }) async {
    final sources = await repo.enabledSources();
    var completed = 0;

    // Phase 1 — fetch every source's network data concurrently (the slow part),
    // capped at [_fetchConcurrency] in flight at a time.
    final fetched = await _pool<FeedSource,
        ({FeedSource source, CollectResult result})>(
      sources,
      _fetchConcurrency,
      (source) async {
        final collector = _collectors.firstWhere(
          (c) => c.handles(source),
          orElse: () => _NoopCollector(),
        );
        final result = await collector.fetch(source);
        completed++;
        onProgress?.call(PipelineProgress(
            source.name, completed, sources.length, result.items.length));
        return (source: source, result: result);
      },
    );

    // Phase 2 — score + store sequentially so dedup stays race-free (SQLite
    // writes are serial anyway; this is fast, local work).
    var newLeads = 0;
    var scanned = 0;
    var failed = 0;
    var rejected = 0;
    final rejectedByReason = <RejectReason, int>{};
    final newScores = <int>[];

    for (final f in fetched) {
      final result = f.result;
      scanned += result.items.length;
      var newHere = 0;
      if (result.status == 'ok') {
        for (final raw in result.items) {
          final s = scorer.score(
            title: raw.title,
            summary: raw.summary,
            publishedDate: raw.publishedDate,
            sourceKind: raw.sourceType,
          );
          // Acceptance gate — drop items the rules reject before storing.
          final reason = scorer.reject(
            title: raw.title,
            summary: raw.summary,
            publishedDate: raw.publishedDate,
            country: raw.country,
            language: raw.language,
            sourceKind: raw.sourceType,
            score: s.score,
          );
          if (reason != null) {
            rejected++;
            rejectedByReason[reason] = (rejectedByReason[reason] ?? 0) + 1;
            continue;
          }
          final scored = raw.copyWith(
            score: s.score,
            isRelevant: s.isRelevant,
            company: s.company,
            projectType: s.projectType,
            detectedCountry: s.country,
            scoreReason: s.reasonText,
          );
          if (await repo.insertIfNew(scored)) {
            newHere++;
            newScores.add(s.score);
          }
        }
      } else {
        failed++;
      }
      newLeads += newHere;

      await repo.updateSource(f.source.copyWith(
        lastStatus: result.status,
        lastError: result.error,
        lastFound: result.items.length,
        lastNew: newHere,
        lastRunAt: DateTime.now().toIso8601String(),
      ));
    }

    return PipelineOutcome(
      sourcesRun: sources.length,
      sourcesFailed: failed,
      newLeads: newLeads,
      scanned: scanned,
      rejected: rejected,
      rejectedByReason: rejectedByReason,
      newScores: newScores,
      finishedAt: DateTime.now(),
    );
  }

  /// Tests [config] (typically the user's unsaved edits) against every stored
  /// lead and reports how many it would keep vs drop, and why. Non-destructive:
  /// nothing is written. Note it can only evaluate leads already stored — items
  /// the *current* rules rejected were never saved, so they can't reappear here.
  Future<DryRunResult> dryRun(ScoringConfig config) async {
    final scorer = KeywordScorer(config);
    final leads = await repo.query(const LeadQuery());
    var kept = 0, dropped = 0;
    final byReason = <RejectReason, int>{};
    for (final l in leads) {
      final s = scorer.score(
        title: l.title,
        summary: l.summary,
        publishedDate: l.publishedDate,
        sourceKind: l.sourceType,
      );
      final r = scorer.reject(
        title: l.title,
        summary: l.summary,
        publishedDate: l.publishedDate,
        country: l.detectedCountry.isNotEmpty ? l.detectedCountry : l.country,
        language: l.language,
        sourceKind: l.sourceType,
        score: s.score,
      );
      if (r == null) {
        kept++;
      } else {
        dropped++;
        byReason[r] = (byReason[r] ?? 0) + 1;
      }
    }
    return DryRunResult(
      total: leads.length,
      kept: kept,
      dropped: dropped,
      byReason: byReason,
    );
  }

  /// Runs [fn] over [items] with at most [concurrency] futures in flight,
  /// preserving input order in the returned list.
  static Future<List<R>> _pool<T, R>(
      List<T> items, int concurrency, Future<R> Function(T) fn) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) break;
        results[i] = await fn(items[i]);
      }
    }

    final n = items.isEmpty ? 0 : min(concurrency, items.length);
    await Future.wait(List.generate(n, (_) => worker()));
    return results.cast<R>();
  }

  /// Re-score every stored lead (e.g. after the user edits the vocabulary).
  /// Skips leads the user has hand-locked.
  Future<int> rescoreAll() async {
    final leads = await repo.query(const LeadQuery());
    var changed = 0;
    for (final lead in leads) {
      if (lead.scoreLocked) continue;
      final s = scorer.score(title: lead.title, summary: lead.summary);
      if (s.score != lead.score ||
          s.company != lead.company ||
          s.country != lead.detectedCountry) {
        await repo.update(lead.copyWith(
          score: s.score,
          isRelevant: s.isRelevant,
          company: s.company,
          projectType: s.projectType,
          detectedCountry: s.country,
          scoreReason: s.reasonText,
        ));
        changed++;
      }
    }
    return changed;
  }
}

class _NoopCollector implements Collector {
  @override
  bool handles(FeedSource source) => true;
  @override
  Future<CollectResult> fetch(FeedSource source) async =>
      CollectResult.failure('no collector for kind ${source.kind.name}');
}
