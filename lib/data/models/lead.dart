import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Where a lead was found. Mirrors the `source_type` values the original
/// Python pipeline stored, so an old intel.db could in principle be imported.
enum SourceKind { rss, googleAlert, worldBank, manual, other }

extension SourceKindX on SourceKind {
  String get label => switch (this) {
        SourceKind.rss => 'News',
        SourceKind.googleAlert => 'Google Alert',
        SourceKind.worldBank => 'World Bank',
        SourceKind.manual => 'Manual',
        SourceKind.other => 'Other',
      };

  String get storageValue => switch (this) {
        SourceKind.rss => 'rss',
        SourceKind.googleAlert => 'google_alert',
        SourceKind.worldBank => 'WorldBank',
        SourceKind.manual => 'manual',
        SourceKind.other => 'other',
      };

  static SourceKind fromStorage(String? v) {
    switch ((v ?? '').toLowerCase()) {
      case 'rss':
        return SourceKind.rss;
      case 'google_alert':
      case 'googlealert':
        return SourceKind.googleAlert;
      case 'worldbank':
        return SourceKind.worldBank;
      case 'manual':
        return SourceKind.manual;
      default:
        return SourceKind.other;
    }
  }
}

/// The sales-pipeline state the *user* assigns to a lead. This is the part the
/// user has full control over — the scorer never touches it.
enum LeadStatus { fresh, reviewing, contacted, won, lost, archived }

extension LeadStatusX on LeadStatus {
  String get label => switch (this) {
        LeadStatus.fresh => 'New',
        LeadStatus.reviewing => 'Reviewing',
        LeadStatus.contacted => 'Contacted',
        LeadStatus.won => 'Won',
        LeadStatus.lost => 'Lost',
        LeadStatus.archived => 'Archived',
      };

  String get storageValue => name;

  static LeadStatus fromStorage(String? v) {
    return LeadStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => LeadStatus.fresh,
    );
  }
}

/// One collected item / potential lead. One-to-one with a row in the `leads`
/// table. Deduplicated by [urlHash] (sha-256 of the URL), exactly like the
/// original pipeline.
class Lead {
  final int? id;
  final String urlHash;
  final String url;
  final String title;
  final String summary; // raw feed summary
  final String published; // raw published string from the feed
  final String publishedDate; // normalized YYYY-MM-DD ('' if unknown)
  final String sourceName;
  final SourceKind sourceType;
  final String language;
  final String country; // the source's region tag
  final String collectedAt; // ISO timestamp we first stored it
  final String imageUrl; // featured image from the feed, '' if none

  // Scoring (filled by KeywordScorer, editable by the user)
  final int score; // 0..10
  final bool isRelevant;
  final String company;
  final String projectType;
  final String detectedCountry; // country the scorer detected in the text
  final String scoreReason; // human-readable "why this score"
  final bool scoreLocked; // user hand-edited the score -> don't overwrite

  // User-controlled fields
  final LeadStatus status;
  final bool favorite;
  final String notes;
  final bool seen; // true once the user has opened this lead

  const Lead({
    this.id,
    required this.urlHash,
    required this.url,
    required this.title,
    this.summary = '',
    this.published = '',
    this.publishedDate = '',
    this.sourceName = '',
    this.sourceType = SourceKind.rss,
    this.language = '',
    this.country = '',
    required this.collectedAt,
    this.imageUrl = '',
    this.score = 0,
    this.isRelevant = false,
    this.company = '',
    this.projectType = '',
    this.detectedCountry = '',
    this.scoreReason = '',
    this.scoreLocked = false,
    this.status = LeadStatus.fresh,
    this.favorite = false,
    this.notes = '',
    this.seen = false,
  });

  static String hashUrl(String url) =>
      sha256.convert(utf8.encode(url.trim())).toString();

  /// A normalized key used to catch the SAME story arriving from different
  /// feeds under different URLs. Lowercases, drops a trailing " - Publisher"
  /// segment (as Google News appends), strips punctuation and collapses
  /// whitespace. Empty for titles with no usable letters (dedup then falls
  /// back to the URL hash).
  String get dedupKey => computeDedupKey(title);

  static final _sepRe = RegExp(r'\s[\-–—|]\s');
  static final _punctRe = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final _wsRe = RegExp(r'\s+');

  static String computeDedupKey(String title) {
    var t = title.toLowerCase().trim();
    // Drop a trailing " - <publisher>" / " — <publisher>" / " | <publisher>"
    // only when the tail is short enough to be a source name (<= 6 words).
    final seps = _sepRe.allMatches(t).toList();
    if (seps.isNotEmpty) {
      final last = seps.last;
      final tail = t.substring(last.end).trim();
      if (tail.isNotEmpty && tail.split(' ').length <= 6) {
        t = t.substring(0, last.start);
      }
    }
    t = t.replaceAll(_punctRe, ' ').replaceAll(_wsRe, ' ').trim();
    return t;
  }

  Lead copyWith({
    int? id,
    int? score,
    bool? isRelevant,
    String? company,
    String? projectType,
    String? detectedCountry,
    String? scoreReason,
    bool? scoreLocked,
    LeadStatus? status,
    bool? favorite,
    String? notes,
    bool? seen,
    String? title,
    String? country,
  }) {
    return Lead(
      id: id ?? this.id,
      urlHash: urlHash,
      url: url,
      title: title ?? this.title,
      summary: summary,
      published: published,
      publishedDate: publishedDate,
      sourceName: sourceName,
      sourceType: sourceType,
      language: language,
      country: country ?? this.country,
      collectedAt: collectedAt,
      imageUrl: imageUrl,
      score: score ?? this.score,
      isRelevant: isRelevant ?? this.isRelevant,
      company: company ?? this.company,
      projectType: projectType ?? this.projectType,
      detectedCountry: detectedCountry ?? this.detectedCountry,
      scoreReason: scoreReason ?? this.scoreReason,
      scoreLocked: scoreLocked ?? this.scoreLocked,
      status: status ?? this.status,
      favorite: favorite ?? this.favorite,
      notes: notes ?? this.notes,
      seen: seen ?? this.seen,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'url_hash': urlHash,
        'url': url,
        'title': title,
        'summary': summary,
        'published': published,
        'published_date': publishedDate,
        'source_name': sourceName,
        'source_type': sourceType.storageValue,
        'language': language,
        'country': country,
        'collected_at': collectedAt,
        'image_url': imageUrl,
        'score': score,
        'is_relevant': isRelevant ? 1 : 0,
        'company': company,
        'project_type': projectType,
        'detected_country': detectedCountry,
        'score_reason': scoreReason,
        'score_locked': scoreLocked ? 1 : 0,
        'status': status.storageValue,
        'favorite': favorite ? 1 : 0,
        'notes': notes,
        'seen': seen ? 1 : 0,
        'dedup_key': dedupKey,
      };

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
        id: m['id'] as int?,
        urlHash: m['url_hash'] as String? ?? '',
        url: m['url'] as String? ?? '',
        title: m['title'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        published: m['published'] as String? ?? '',
        publishedDate: m['published_date'] as String? ?? '',
        sourceName: m['source_name'] as String? ?? '',
        sourceType: SourceKindX.fromStorage(m['source_type'] as String?),
        language: m['language'] as String? ?? '',
        country: m['country'] as String? ?? '',
        collectedAt: m['collected_at'] as String? ?? '',
        imageUrl: m['image_url'] as String? ?? '',
        score: (m['score'] as int?) ?? 0,
        isRelevant: (m['is_relevant'] as int? ?? 0) == 1,
        company: m['company'] as String? ?? '',
        projectType: m['project_type'] as String? ?? '',
        detectedCountry: m['detected_country'] as String? ?? '',
        scoreReason: m['score_reason'] as String? ?? '',
        scoreLocked: (m['score_locked'] as int? ?? 0) == 1,
        status: LeadStatusX.fromStorage(m['status'] as String?),
        favorite: (m['favorite'] as int? ?? 0) == 1,
        notes: m['notes'] as String? ?? '',
        seen: (m['seen'] as int? ?? 0) == 1,
      );
}
