import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The FFI SQLite bundled for Windows/Linux disables double-quoted string
/// literals (SQLITE_DQS=0), so `published_date = ""` there is parsed as an
/// unknown column and throws. This guards that our ORDER BY uses single-quoted
/// empty strings and works on strict SQLite.
void main() {
  test('leads ORDER BY runs on strict (FFI) SQLite', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE leads(id INTEGER PRIMARY KEY, score INTEGER, published_date TEXT)');
    await db.insert('leads', {'score': 5, 'published_date': ''});
    await db.insert('leads', {'score': 9, 'published_date': '2026-01-01'});

    const order =
        "score DESC, (published_date IS NULL OR published_date = ''), "
        "published_date DESC, id DESC";
    final rows = await db.query('leads', orderBy: order);

    expect(rows.length, 2);
    expect(rows.first['score'], 9); // highest score first
    await db.close();
  });
}
