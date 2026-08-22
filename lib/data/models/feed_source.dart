import 'lead.dart';

/// A configurable feed the pipeline pulls from. Ported from the original
/// sources.yaml registry, but now fully user-editable at runtime and stored
/// in the local DB so the user has complete control over what is collected.
class FeedSource {
  final int? id;
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
}
