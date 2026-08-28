import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens (and, on first launch, creates) the local SQLite database.
///
/// Cross-platform: on Windows/Linux we use the FFI factory; on macOS/Android
/// the native sqflite factory works out of the box. There is no server and no
/// remote DB — everything lives in this one file on the device.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final path = p.join(dir.path, 'bastak_leads.db');
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  // Bump this and add a step to [_migrations] whenever the schema changes.
  static const _dbVersion = 5;

  /// Ordered, additive migrations keyed by the version they upgrade *to*.
  /// Running from any older version applies each step in turn, so existing
  /// installs are never wiped.
  static final Map<int, Future<void> Function(Database)> _migrations = {
    2: (db) async {
      await db.execute('ALTER TABLE leads ADD COLUMN dedup_key TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_leads_dedup ON leads(dedup_key)');
    },
    3: (db) async {
      await db.execute('ALTER TABLE leads ADD COLUMN image_url TEXT');
    },
    4: (db) async {
      await db.execute(
          'ALTER TABLE leads ADD COLUMN seen INTEGER NOT NULL DEFAULT 0');
    },
    // The feed registry moved to the Firestore `Sources` collection; the local
    // `sources` table is now just a mirror. Track each row's Firestore doc id
    // so edits/deletes can target the cloud document.
    5: (db) async {
      await db.execute('ALTER TABLE sources ADD COLUMN doc_id TEXT');
    },
  };

  Future<void> _onUpgrade(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      final step = _migrations[v];
      if (step != null) await step(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE leads (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        url_hash       TEXT NOT NULL UNIQUE,
        url            TEXT NOT NULL,
        title          TEXT,
        summary        TEXT,
        published      TEXT,
        published_date TEXT,
        source_name    TEXT,
        source_type    TEXT,
        language       TEXT,
        country        TEXT,
        collected_at   TEXT NOT NULL,
        score          INTEGER NOT NULL DEFAULT 0,
        is_relevant    INTEGER NOT NULL DEFAULT 0,
        company        TEXT,
        project_type   TEXT,
        detected_country TEXT,
        score_reason   TEXT,
        score_locked   INTEGER NOT NULL DEFAULT 0,
        status         TEXT NOT NULL DEFAULT 'fresh',
        favorite       INTEGER NOT NULL DEFAULT 0,
        notes          TEXT NOT NULL DEFAULT '',
        dedup_key      TEXT,
        image_url      TEXT,
        seen           INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_leads_score ON leads(score)');
    await db.execute('CREATE INDEX idx_leads_pubdate ON leads(published_date)');
    await db.execute('CREATE INDEX idx_leads_country ON leads(country)');
    await db.execute('CREATE INDEX idx_leads_status ON leads(status)');
    await db.execute('CREATE INDEX idx_leads_dedup ON leads(dedup_key)');

    await db.execute('''
      CREATE TABLE sources (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id      TEXT,
        name        TEXT NOT NULL,
        url         TEXT NOT NULL,
        kind        TEXT NOT NULL,
        language    TEXT,
        country     TEXT,
        enabled     INTEGER NOT NULL DEFAULT 1,
        built_in    INTEGER NOT NULL DEFAULT 0,
        last_status TEXT,
        last_error  TEXT,
        last_found  INTEGER NOT NULL DEFAULT 0,
        last_new    INTEGER NOT NULL DEFAULT 0,
        last_run_at TEXT
      )
    ''');

    // The `sources` table starts empty now — the registry is seeded into and
    // loaded from the Firestore `Sources` collection (see SourceRepository),
    // then mirrored here on each app open for the offline pipeline.
  }
}
