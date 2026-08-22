import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models/feed_source.dart';
import 'models/lead.dart';

/// The filter/sort criteria that drive the leads list. Everything the user can
/// tweak from the UI to slice the data lives here.
class LeadQuery {
  final String search;
  final int minScore;
  final String? country; // matches country OR detected_country
  final Set<LeadStatus> statuses;
  final Set<SourceKind> sources;
  final bool favoritesOnly;
  final bool freshOnly; // published within freshDays
  final int freshDays;
  final LeadSort sort;

  const LeadQuery({
    this.search = '',
    this.minScore = 0,
    this.country,
    this.statuses = const {},
    this.sources = const {},
    this.favoritesOnly = false,
    this.freshOnly = false,
    this.freshDays = 90,
    this.sort = LeadSort.scoreDesc,
  });

  LeadQuery copyWith({
    String? search,
    int? minScore,
    Object? country = _sentinel,
    Set<LeadStatus>? statuses,
    Set<SourceKind>? sources,
    bool? favoritesOnly,
    bool? freshOnly,
    int? freshDays,
    LeadSort? sort,
  }) {
    return LeadQuery(
      search: search ?? this.search,
      minScore: minScore ?? this.minScore,
      country: country == _sentinel ? this.country : country as String?,
      statuses: statuses ?? this.statuses,
      sources: sources ?? this.sources,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      freshOnly: freshOnly ?? this.freshOnly,
      freshDays: freshDays ?? this.freshDays,
      sort: sort ?? this.sort,
    );
  }

  static const _sentinel = Object();
}

enum LeadSort { scoreDesc, dateDesc, dateAsc, titleAsc }

class LeadStats {
  final int total;
  final int hot; // score >= 8
  final int warm; // score 4..7
  final int fresh; // published within window
  final int favorites;
  const LeadStats(
      {this.total = 0,
      this.hot = 0,
      this.warm = 0,
      this.fresh = 0,
      this.favorites = 0});
}

class LeadRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ---- Leads -------------------------------------------------------------

  /// Inserts a lead if its url_hash is new. Returns true if inserted.
  Future<bool> insertIfNew(Lead lead) async {
    final db = await _db;
    final id = await db.insert(
      'leads',
      lead.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  Future<void> update(Lead lead) async {
    final db = await _db;
    await db.update('leads', lead.toMap(),
        where: 'id = ?', whereArgs: [lead.id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('leads', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAll() async {
    final db = await _db;
    return db.delete('leads');
  }

  Future<void> deleteMany(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('leads',
        where: 'id IN ($placeholders)', whereArgs: ids.toList());
  }

  Future<List<Lead>> query(LeadQuery q) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (q.search.trim().isNotEmpty) {
      where.add('(title LIKE ? OR summary LIKE ? OR company LIKE ? '
          'OR source_name LIKE ?)');
      final like = '%${q.search.trim()}%';
      args.addAll([like, like, like, like]);
    }
    if (q.minScore > 0) {
      where.add('score >= ?');
      args.add(q.minScore);
    }
    if (q.country != null && q.country!.isNotEmpty) {
      where.add('(country = ? OR detected_country = ?)');
      args.addAll([q.country, q.country]);
    }
    if (q.statuses.isNotEmpty) {
      final ph = List.filled(q.statuses.length, '?').join(',');
      where.add('status IN ($ph)');
      args.addAll(q.statuses.map((s) => s.storageValue));
    }
    if (q.sources.isNotEmpty) {
      final ph = List.filled(q.sources.length, '?').join(',');
      where.add('source_type IN ($ph)');
      args.addAll(q.sources.map((s) => s.storageValue));
    }
    if (q.favoritesOnly) where.add('favorite = 1');
    if (q.freshOnly) {
      final cutoff = _cutoff(q.freshDays);
      where.add("published_date != '' AND published_date IS NOT NULL "
          'AND published_date >= ?');
      args.add(cutoff);
    }

    final order = switch (q.sort) {
      LeadSort.scoreDesc =>
        'score DESC, (published_date IS NULL OR published_date = ""), '
            'published_date DESC, id DESC',
      LeadSort.dateDesc =>
        '(published_date IS NULL OR published_date = ""), '
            'published_date DESC, id DESC',
      LeadSort.dateAsc =>
        '(published_date IS NULL OR published_date = ""), published_date ASC',
      LeadSort.titleAsc => 'title COLLATE NOCASE ASC',
    };

    final rows = await db.query(
      'leads',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: order,
    );
    return rows.map(Lead.fromMap).toList();
  }

  Future<LeadStats> stats({int freshDays = 90}) async {
    final db = await _db;
    final cutoff = _cutoff(freshDays);
    Future<int> count(String where, [List<Object?> a = const []]) async {
      final r = await db
          .rawQuery('SELECT COUNT(*) c FROM leads WHERE $where', a);
      return (r.first['c'] as int?) ?? 0;
    }

    final total = await count('1=1');
    final hot = await count('score >= 8');
    final warm = await count('score >= 4 AND score < 8');
    final fresh = await count(
        "published_date != '' AND published_date >= ?", [cutoff]);
    final favorites = await count('favorite = 1');
    return LeadStats(
        total: total, hot: hot, warm: warm, fresh: fresh, favorites: favorites);
  }

  /// Distinct non-empty countries present across both tag and detected columns.
  Future<List<String>> countries() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT country AS c FROM leads WHERE country != '' AND country IS NOT NULL
      UNION
      SELECT DISTINCT detected_country AS c FROM leads
        WHERE detected_country != '' AND detected_country IS NOT NULL
      ORDER BY c
    ''');
    return rows.map((r) => r['c'] as String).toList();
  }

  // ---- Sources -----------------------------------------------------------

  Future<List<FeedSource>> allSources() async {
    final db = await _db;
    final rows = await db.query('sources', orderBy: 'enabled DESC, name ASC');
    return rows.map(FeedSource.fromMap).toList();
  }

  Future<List<FeedSource>> enabledSources() async {
    final db = await _db;
    final rows =
        await db.query('sources', where: 'enabled = 1', orderBy: 'name');
    return rows.map(FeedSource.fromMap).toList();
  }

  Future<int> insertSource(FeedSource s) async {
    final db = await _db;
    return db.insert('sources', s.toMap());
  }

  Future<void> updateSource(FeedSource s) async {
    final db = await _db;
    await db.update('sources', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
  }

  Future<void> deleteSource(int id) async {
    final db = await _db;
    await db.delete('sources', where: 'id = ?', whereArgs: [id]);
  }

  static String _cutoff(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
