import 'lead.dart';

/// A configurable feed the pipeline pulls from. Ported from the original
/// sources.yaml registry. The registry now lives in the Firestore `Sources`
/// collection (authored by admins, readable by everyone), and is mirrored into
/// the local DB on load so the offline/background pipeline keeps working.
///
/// Two identities coexist for that reason:
///   * [docId]  — the Firestore document id. Present on cloud-loaded sources;
///                the stable key used for edits/deletes.
///   * [id]     — the local sqflite rowid of the mirror row. Used only by the
///                collection pipeline, which still reads the local table.
class FeedSource {
  final int? id;
  final String? docId;
  final String name;
  final String url;
  final SourceKind kind; // rss / googleAlert / worldBank
  final String language;
  final String country;
  final bool enabled;
  final bool builtIn; // shipped default vs user-added
  final String? lastStatus; // ok | error | skipped
  final String? lastError;
  final int lastFound;
  final int lastNew;
  final String? lastRunAt;

  const FeedSource({
    this.id,
    this.docId,
    required this.name,
    required this.url,
    this.kind = SourceKind.rss,
    this.language = 'en',
    this.country = 'global',
    this.enabled = true,
    this.builtIn = false,
    this.lastStatus,
    this.lastError,
    this.lastFound = 0,
    this.lastNew = 0,
    this.lastRunAt,
  });

  bool get isWorldBank => kind == SourceKind.worldBank;

  FeedSource copyWith({
    int? id,
    String? docId,
    String? name,
    String? url,
    SourceKind? kind,
    String? language,
    String? country,
    bool? enabled,
    bool? builtIn,
    String? lastStatus,
    String? lastError,
    int? lastFound,
    int? lastNew,
    String? lastRunAt,
  }) {
    return FeedSource(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      name: name ?? this.name,
      url: url ?? this.url,
      kind: kind ?? this.kind,
      language: language ?? this.language,
      country: country ?? this.country,
      enabled: enabled ?? this.enabled,
      builtIn: builtIn ?? this.builtIn,
      lastStatus: lastStatus ?? this.lastStatus,
      lastError: lastError,
      lastFound: lastFound ?? this.lastFound,
      lastNew: lastNew ?? this.lastNew,
      lastRunAt: lastRunAt ?? this.lastRunAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'doc_id': docId,
        'name': name,
        'url': url,
        'kind': kind.storageValue,
        'language': language,
        'country': country,
        'enabled': enabled ? 1 : 0,
        'built_in': builtIn ? 1 : 0,
        'last_status': lastStatus,
        'last_error': lastError,
        'last_found': lastFound,
        'last_new': lastNew,
        'last_run_at': lastRunAt,
      };

  factory FeedSource.fromMap(Map<String, Object?> m) => FeedSource(
        id: m['id'] as int?,
        docId: m['doc_id'] as String?,
        name: m['name'] as String? ?? '',
        url: m['url'] as String? ?? '',
        kind: SourceKindX.fromStorage(m['kind'] as String?),
        language: m['language'] as String? ?? 'en',
        country: m['country'] as String? ?? 'global',
        enabled: (m['enabled'] as int? ?? 1) == 1,
        builtIn: (m['built_in'] as int? ?? 0) == 1,
        lastStatus: m['last_status'] as String?,
        lastError: m['last_error'] as String?,
        lastFound: (m['last_found'] as int?) ?? 0,
        lastNew: (m['last_new'] as int?) ?? 0,
        lastRunAt: m['last_run_at'] as String?,
      );

  /// The document body written to the Firestore `Sources` collection. Only the
  /// authored configuration is stored here — run health (last_status etc.) is a
  /// local, per-device concern and stays in the sqflite mirror. Booleans stay
  /// native (not 0/1) since Firestore has a real bool type.
  Map<String, Object?> toFirestore() => {
        'name': name,
        'url': url,
        'kind': kind.storageValue,
        'language': language,
        'country': country,
        'enabled': enabled,
        'builtIn': builtIn,
      };

  factory FeedSource.fromFirestore(String docId, Map<String, Object?> m) =>
      FeedSource(
        docId: docId,
        name: m['name'] as String? ?? '',
        url: m['url'] as String? ?? '',
        kind: SourceKindX.fromStorage(m['kind'] as String?),
        language: m['language'] as String? ?? 'en',
        country: m['country'] as String? ?? 'global',
        // Tolerate both the Firestore bool and a legacy 0/1 int.
        enabled: _asBool(m['enabled'], fallback: true),
        builtIn: _asBool(m['builtIn'], fallback: false),
      );

  static bool _asBool(Object? v, {required bool fallback}) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    return fallback;
  }
}
