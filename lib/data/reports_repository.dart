import 'app_database.dart';
import 'package:sqflite/sqflite.dart';

/// A labelled count, optionally with a "hot" (score>=8) sub-count.
class CountRow {
  final String label;
  final int count;
  final int hot;
  const CountRow(this.label, this.count, {this.hot = 0});
}

class SourcePerf {
  final String name;
  final int total;
  final int hot;
  final double avgScore;
  const SourcePerf(this.name, this.total, this.hot, this.avgScore);
}

/// Overall snapshot numbers for the Reports overview.
class ReportOverview {
  final int total, hot, warm, cold, relevant, seen, favorites, fresh, withCompany;
  final double avgScore;
  const ReportOverview({
    this.total = 0,
    this.hot = 0,
    this.warm = 0,
    this.cold = 0,
    this.relevant = 0,
    this.seen = 0,
    this.favorites = 0,
    this.fresh = 0,
    this.withCompany = 0,
    this.avgScore = 0,
  });
}

/// Read-only aggregate queries powering the Reports tab.
class ReportsRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  static String _cutoff(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Future<ReportOverview> overview({int freshDays = 90}) async {
    final db = await _db;
    Future<int> c(String w, [List<Object?> a = const []]) async {
      final r = await db.rawQuery('SELECT COUNT(*) n FROM leads WHERE $w', a);
      return (r.first['n'] as int?) ?? 0;
    }

    final total = await c('1=1');
    final avgRow =
        await db.rawQuery('SELECT AVG(score) a FROM leads');
    final avg = (avgRow.first['a'] as num?)?.toDouble() ?? 0;
    return ReportOverview(
      total: total,
      hot: await c('score >= 8'),
      warm: await c('score >= 4 AND score < 8'),
      cold: await c('score < 4'),
      relevant: await c('is_relevant = 1'),
      seen: await c('seen = 1'),
      favorites: await c('favorite = 1'),
      fresh: await c("published_date != '' AND published_date >= ?",
          [_cutoff(freshDays)]),
      withCompany: await c("company != '' AND company IS NOT NULL"),
      avgScore: avg,
    );
  }

  /// Count for each score 0..10.
  Future<List<int>> scoreHistogram() async {
    final db = await _db;
    final rows = await db
        .rawQuery('SELECT score, COUNT(*) c FROM leads GROUP BY score');
    final out = List<int>.filled(11, 0);
    for (final r in rows) {
      final s = (r['score'] as int?) ?? 0;
      if (s >= 0 && s <= 10) out[s] = (r['c'] as int?) ?? 0;
    }
    return out;
  }

  Future<List<CountRow>> byStatus() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT status, COUNT(*) c FROM leads GROUP BY status');
    return rows
        .map((r) => CountRow((r['status'] as String?) ?? 'fresh',
            (r['c'] as int?) ?? 0))
        .toList();
  }

  Future<List<CountRow>> topCountries({int limit = 10}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(detected_country,''), NULLIF(country,''), 'Unknown') AS ctry,
             COUNT(*) c,
             SUM(CASE WHEN score >= 8 THEN 1 ELSE 0 END) hot
      FROM leads GROUP BY ctry ORDER BY c DESC LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => CountRow(r['ctry'] as String, (r['c'] as int?) ?? 0,
            hot: (r['hot'] as int?) ?? 0))
        .toList();
  }

  Future<List<CountRow>> byProjectType() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT CASE WHEN project_type IS NULL OR project_type = '' THEN 'none'
                  ELSE project_type END AS pt,
             COUNT(*) c
      FROM leads GROUP BY pt ORDER BY c DESC
    ''');
    return rows
        .map((r) => CountRow(r['pt'] as String, (r['c'] as int?) ?? 0))
        .toList();
  }

  Future<List<SourcePerf>> sourcePerformance({int limit = 20}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT source_name AS s, COUNT(*) total,
             SUM(CASE WHEN score >= 8 THEN 1 ELSE 0 END) hot,
             AVG(score) avg
      FROM leads WHERE source_name != '' GROUP BY s
      ORDER BY total DESC LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => SourcePerf(
              r['s'] as String,
              (r['total'] as int?) ?? 0,
              (r['hot'] as int?) ?? 0,
              (r['avg'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }

  /// Leads collected per day for the last [days] days (oldest→newest).
  Future<List<CountRow>> intakeByDay({int days = 30}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT substr(collected_at, 1, 10) AS d, COUNT(*) c
      FROM leads WHERE substr(collected_at,1,10) >= ?
      GROUP BY d ORDER BY d
    ''', [_cutoff(days)]);
    return rows
        .map((r) => CountRow((r['d'] as String?) ?? '', (r['c'] as int?) ?? 0))
        .toList();
  }

  /// Per-country breakdown into cold/warm/hot bands (for a stacked bar chart).
  Future<List<({String label, int cold, int warm, int hot})>>
      scoreBandsByCountry({int limit = 6}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(detected_country,''), NULLIF(country,''), 'Unknown') AS ctry,
             SUM(CASE WHEN score < 4 THEN 1 ELSE 0 END) cold,
             SUM(CASE WHEN score >= 4 AND score < 8 THEN 1 ELSE 0 END) warm,
             SUM(CASE WHEN score >= 8 THEN 1 ELSE 0 END) hot,
             COUNT(*) total
      FROM leads GROUP BY ctry ORDER BY total DESC LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => (
              label: r['ctry'] as String,
              cold: (r['cold'] as int?) ?? 0,
              warm: (r['warm'] as int?) ?? 0,
              hot: (r['hot'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Daily total + hot counts for the last [days] days (for a dual-series
  /// trend). Returns a map keyed by 'yyyy-MM-dd'.
  Future<Map<String, ({int total, int hot})>> intakeWithHot(
      {int days = 30}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT substr(collected_at, 1, 10) AS d, COUNT(*) total,
             SUM(CASE WHEN score >= 8 THEN 1 ELSE 0 END) hot
      FROM leads WHERE substr(collected_at,1,10) >= ?
      GROUP BY d
    ''', [_cutoff(days)]);
    return {
      for (final r in rows)
        (r['d'] as String? ?? ''): (
          total: (r['total'] as int?) ?? 0,
          hot: (r['hot'] as int?) ?? 0,
        ),
    };
  }

  Future<List<CountRow>> topCompanies({int limit = 12}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT company AS c, COUNT(*) n
      FROM leads WHERE company != '' AND company IS NOT NULL
      GROUP BY company ORDER BY n DESC LIMIT ?
    ''', [limit]);
    return rows
        .map((r) => CountRow(r['c'] as String, (r['n'] as int?) ?? 0))
        .toList();
  }
}
