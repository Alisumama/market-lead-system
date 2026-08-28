import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/app_user.dart';

/// Data access for the application users, stored in the Firestore `Users`
/// collection. This is the cloud counterpart to [LeadRepository] (which is
/// local sqflite); the two are independent — leads stay on-device, users live
/// in Firestore so they can be managed across installs.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const collection = 'Users';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collection);

  /// Live stream of all users, newest first. Backs the list screen so edits
  /// from any device show up without a manual refresh.
  Stream<List<AppUser>> watchAll() {
    return _col.orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => AppUser.fromMap(d.id, d.data()))
              .toList(growable: false),
        );
  }

  Future<List<AppUser>> all() async {
    final snap = await _col.orderBy('name').get();
    return snap.docs
        .map((d) => AppUser.fromMap(d.id, d.data()))
        .toList(growable: false);
  }

  Future<AppUser?> byId(String id) async {
    final doc = await _col.doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    return AppUser.fromMap(doc.id, data);
  }

  /// Case-insensitive lookup by email. Returns null when no user matches.
  Future<AppUser?> byEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final snap = await _col.get();
    for (final d in snap.docs) {
      if ((d.data()['email'] as String? ?? '').trim().toLowerCase() ==
          normalized) {
        return AppUser.fromMap(d.id, d.data());
      }
    }
    return null;
  }

  /// True once at least one user exists — drives the login screen's first-run
  /// "create the first admin" bootstrap.
  Future<bool> anyExists() async {
    final snap = await _col.limit(1).get();
    return snap.docs.isNotEmpty;
  }

  /// True if another user already uses [email] (case-insensitive). Pass the id
  /// of the user being edited as [exceptId] so it doesn't clash with itself.
  Future<bool> emailTaken(String email, {String? exceptId}) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final snap = await _col.get();
    return snap.docs.any((d) =>
        d.id != exceptId &&
        (d.data()['email'] as String? ?? '').trim().toLowerCase() ==
            normalized);
  }

  /// Creates a new user document and returns its generated id. Server time is
  /// used for both timestamps so ordering is consistent regardless of device
  /// clocks.
  Future<String> add(AppUser user) async {
    final ref = await _col.add({
      ...user.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(AppUser user) async {
    final id = user.id;
    if (id == null) {
      throw ArgumentError('Cannot update a user with no id');
    }
    await _col.doc(id).update({
      ...user.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates everything except the PIN. Used when the admin edits a user but
  /// leaves the PIN field blank, meaning "keep the existing PIN".
  Future<void> updateKeepingPin(AppUser user) async {
    final id = user.id;
    if (id == null) {
      throw ArgumentError('Cannot update a user with no id');
    }
    final map = user.toMap()..remove('pinHash');
    await _col.doc(id).update({
      ...map,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Enables or disables a user without touching any other field.
  Future<void> setActive(String id, bool active) async {
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Replaces a user's PIN. Takes the already-hashed value so the raw PIN never
  /// reaches this layer.
  Future<void> setPinHash(String id, String pinHash) async {
    await _col.doc(id).update({
      'pinHash': pinHash,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
