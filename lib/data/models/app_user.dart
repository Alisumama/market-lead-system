import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The access level assigned to an application user. Mirrors the pattern used by
/// [LeadStatus] in models/lead.dart — a small enum with a human [label] and a
/// stable [storageValue] so the string persisted in Firestore never changes
/// even if the display text does.
enum UserRole { admin, manager, viewer }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.manager => 'Manager',
        UserRole.viewer => 'Viewer',
      };

  String get storageValue => name;

  static UserRole fromStorage(String? v) {
    return UserRole.values.firstWhere(
      (r) => r.name == v,
      orElse: () => UserRole.viewer,
    );
  }
}

/// One application user, stored as a document in the Firestore `Users`
/// collection. Named [AppUser] to avoid colliding with Firebase's own `User`
/// type from firebase_auth should that ever be added.
///
/// The PIN is never stored in the clear: only [pinHash] is persisted, produced
/// by the same sha-256 + salt scheme as the local app lock (see AuthService), so
/// a leaked database can't reveal anyone's PIN.
class AppUser {
  /// Firestore document id. Null for a user that hasn't been written yet.
  final String? id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String pinHash;

  /// Whether the account is enabled. An inactive user is kept in the collection
  /// (history, re-enabling) but is meant to be barred from signing in.
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppUser({
    this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.role = UserRole.viewer,
    this.pinHash = '',
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Same salt + algorithm as AuthService so the two PIN representations stay
  /// interchangeable if login is ever wired up against this collection.
  static const _salt = 'bastak-leads-v1';

  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('$_salt:$pin')).toString();

  bool verifyPin(String pin) => pinHash.isNotEmpty && pinHash == hashPin(pin);

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    String? pinHash,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      pinHash: pinHash ?? this.pinHash,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// The document body written to Firestore. The doc id is stored separately by
  /// Firestore itself, so it isn't part of the map. Timestamps are left to the
  /// repository, which stamps them with server time on write.
  Map<String, Object?> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role.storageValue,
        'pinHash': pinHash,
        'active': active,
      };

  factory AppUser.fromMap(String id, Map<String, Object?> m) => AppUser(
        id: id,
        name: m['name'] as String? ?? '',
        email: m['email'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        role: UserRoleX.fromStorage(m['role'] as String?),
        pinHash: m['pinHash'] as String? ?? '',
        // Legacy docs written before this field existed are treated as active.
        active: m['active'] as bool? ?? true,
        createdAt: _asDate(m['createdAt']),
        updatedAt: _asDate(m['updatedAt']),
      );

  /// Firestore returns a `Timestamp` for server-stamped fields, but we keep this
  /// tolerant of an int millis value or an ISO string too, so the model can be
  /// hydrated from other sources in tests.
  static DateTime? _asDate(Object? v) {
    if (v == null) return null;
    // Firestore Timestamp exposes toDate() via dynamic dispatch; avoid importing
    // the type here so the model stays free of the cloud_firestore dependency.
    try {
      final d = (v as dynamic).toDate();
      if (d is DateTime) return d;
    } catch (_) {}
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
