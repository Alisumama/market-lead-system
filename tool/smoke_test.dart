// ignore_for_file: avoid_print
// Standalone end-to-end smoke test (no GUI): fetches a couple of real feeds,
// scores them, and prints a summary. Run with:  dart run tool/smoke_test.dart
import 'package:bastak_leads/collectors/rss_collector.dart';
import 'package:bastak_leads/collectors/worldbank_collector.dart';
import 'package:bastak_leads/data/default_sources.dart';
import 'package:bastak_leads/data/models/lead.dart';
import 'package:bastak_leads/scoring/keyword_scorer.dart';

Future<void> main() async {
  const scorer = KeywordScorer();
  final rss = RssCollector();
  final wb = WorldBankCollector();

  final rssSource = kDefaultSources
      .firstWhere((s) => s.name.startsWith('Mill tenders'));
  final wbSource =
      kDefaultSources.firstWhere((s) => s.kind == SourceKind.worldBank);

  print('Fetching RSS: ${rssSource.name}');
  final r1 = await rss.fetch(rssSource);
  print('  status=${r1.status} items=${r1.items.length} err=${r1.error ?? "-"}');

  print('Fetching World Bank procurement notices…');
  final r2 = await wb.fetch(wbSource);
  print('  status=${r2.status} items=${r2.items.length} err=${r2.error ?? "-"}');

  final all = [...r1.items, ...r2.items];
  final scored = all.map((l) {
    final s = scorer.score(title: l.title, summary: l.summary);
    return (lead: l, res: s);
  }).toList()
    ..sort((a, b) => b.res.score.compareTo(a.res.score));

  print('\nTop scored leads:');
  for (final e in scored.take(8)) {
    print('  [${e.res.score}] ${e.lead.title}');
    print('        ${e.res.reasonText}');
  }
  print('\nTotal collected: ${all.length}');
}
