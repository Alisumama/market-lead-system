import 'package:cloud_firestore/cloud_firestore.dart';

import '../util/url.dart';
import 'default_sources.dart';
import 'models/feed_source.dart';

/// Cloud storage for the feed registry, in the Firestore `Sources` collection.
/// This is the source of truth: admins author/enable sources here and every
/// client loads them on open. The local sqflite `sources` table is only a
/// per-device mirror the collection pipeline reads (see AppState.syncSources).
///
/// A source is identified by its normalized URL — the collection is kept free of
/// duplicate URLs by [add] (upsert), [seedDefaultsIfEmpty] and [dedupeByUrl].
class SourceRepository {
  SourceRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const collection = 'Sources';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collection);

  /// Canonical form used to compare two URLs for equality. Delegates to the
  /// shared [normalizeFeedUrl] so every de-dup path uses identical logic.
  static String normalizeUrl(String raw) => normalizeFeedUrl(raw);

  Future<List<FeedSource>> all() async {
    final snap = await _col.orderBy('name').get();
    return snap.docs
        .map((d) => FeedSource.fromFirestore(d.id, d.data()))
        .toList(growable: false);
  }

  Stream<List<FeedSource>> watchAll() {
    return _col.orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => FeedSource.fromFirestore(d.id, d.data()))
              .toList(growable: false),
        );
  }

  /// Returns the docId of the source whose URL matches [url] (ignoring
  /// [exceptDocId]), or null if none — used to keep URLs unique.
  Future<String?> docIdForUrl(String url, {String? exceptDocId}) async {
    final key = normalizeUrl(url);
    if (key.isEmpty) return null;
    final snap = await _col.get();
    for (final d in snap.docs) {
      if (d.id == exceptDocId) continue;
      if (normalizeUrl(d.data()['url'] as String? ?? '') == key) return d.id;
    }
    return null;
  }

  /// Adds [s], or updates the existing document if one already has the same URL
  /// — so the same feed can never be stored twice. Returns the docId written.
  Future<String> add(FeedSource s) async {
    final existing = await docIdForUrl(s.url);
    if (existing != null) {
      await _col.doc(existing).set(s.toFirestore(), SetOptions(merge: true));
      return existing;
    }
    final ref = await _col.add(s.toFirestore());
    return ref.id;
  }

  Future<void> update(FeedSource s) async {
    final id = s.docId;
    if (id == null) throw ArgumentError('Source has no docId');
    await _col.doc(id).set(s.toFirestore(), SetOptions(merge: true));
  }

  Future<void> delete(String docId) => _col.doc(docId).delete();

  /// Seeds the shipped defaults the first time the collection is empty, so a
  /// fresh Firebase project starts with the same registry the app used to ship
  /// locally. A no-op once any source exists. The defaults are de-duplicated by
  /// URL first so a seed can never introduce two of the same feed. Best-effort:
  /// callers ignore failures (e.g. rules not yet deployed).
  Future<int> seedDefaultsIfEmpty() async {
    final existing = await _col.limit(1).get();
    if (existing.docs.isNotEmpty) return 0;
    final seen = <String>{};
    final batch = _db.batch();
    var n = 0;
    for (final s in kDefaultSources) {
      final key = normalizeUrl(s.url);
      if (key.isEmpty || !seen.add(key)) continue; // skip blanks + dupes
      batch.set(_col.doc(), s.copyWith(builtIn: true).toFirestore());
      n++;
    }
    await batch.commit();
    return n;
  }

  /// Removes duplicate-URL documents that may already exist (e.g. from an older
  /// build that didn't upsert), keeping a single doc per URL — preferring an
  /// enabled one. Returns how many documents were deleted. Best-effort.
  Future<int> dedupeByUrl() async {
    final snap = await _col.get();
    final keepByUrl = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final toDelete = <String>[];
    for (final d in snap.docs) {
      final key = normalizeUrl(d.data()['url'] as String? ?? '');
      if (key.isEmpty) continue;
      final kept = keepByUrl[key];
      if (kept == null) {
        keepByUrl[key] = d;
        continue;
      }
      // Prefer to keep an enabled doc; delete the other.
      final keptEnabled = _enabled(kept);
      final thisEnabled = _enabled(d);
      if (thisEnabled && !keptEnabled) {
        toDelete.add(kept.id);
        keepByUrl[key] = d;
      } else {
        toDelete.add(d.id);
      }
    }
    if (toDelete.isEmpty) return 0;
    final batch = _db.batch();
    for (final id in toDelete) {
      batch.delete(_col.doc(id));
    }
    await batch.commit();
    return toDelete.length;
  }

  static bool _enabled(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final v = d.data()['enabled'];
    if (v is bool) return v;
    if (v is int) return v == 1;
    return true;
  }
}
