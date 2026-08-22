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
  final List<int> newScores; // scores of the newly-inserted leads
  final DateTime finishedAt;
  const PipelineOutcome({
    required this.sourcesRun,
    required this.sourcesFailed,
    required this.newLeads,
    required this.scanned,
    required this.newScores,
    required this.finishedAt,
  });

  int newAtOrAbove(int minScore) =>
      minScore <= 0 ? newLeads : newScores.where((s) => s >= minScore).length;
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

  Future<PipelineOutcome> run({
    void Function(PipelineProgress)? onProgress,
  }) async {
    final sources = await repo.enabledSources();
    var newLeads = 0;
    var scanned = 0;
    var failed = 0;
    final newScores = <int>[];

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final collector = _collectors.firstWhere(
        (c) => c.handles(source),
        orElse: () => _NoopCollector(),
      );
      final result = await collector.fetch(source);
      scanned += result.items.length;

      var newHere = 0;
      if (result.status == 'ok') {
        for (final raw in result.items) {
          final s = scorer.score(title: raw.title, summary: raw.summary);
          final scored = raw.copyWith(
            score: s.score,
            isRelevant: s.isRelevant,
            company: s.company,
            projectType: s.projectType,
            detectedCountry: s.country,
            scoreReason: s.reasonText,
          );
          final inserted = await repo.insertIfNew(scored);
          if (inserted) {
            newHere++;
            newScores.add(s.score);
          }
        }
      } else {
        failed++;
      }
      newLeads += newHere;

      await repo.updateSource(source.copyWith(
        lastStatus: result.status,
        lastError: result.error,
        lastFound: result.items.length,
        lastNew: newHere,
        lastRunAt: DateTime.now().toIso8601String(),
      ));

      onProgress?.call(
          PipelineProgress(source.name, i + 1, sources.length, newHere));
    }

    return PipelineOutcome(
      sourcesRun: sources.length,
      sourcesFailed: failed,
      newLeads: newLeads,
      scanned: scanned,
      newScores: newScores,
      finishedAt: DateTime.now(),
    );
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
