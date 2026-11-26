import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../data/models/feed_source.dart';
import '../data/models/lead.dart';
import '../util/text.dart';
import 'collector.dart';
import 'date_utils.dart';
import 'url_unwrap.dart';

/// Fetches RSS 2.0 and Atom feeds and turns each entry into a [Lead].
/// Pure-Dart replacement for feedparser + collect.py.
class RssCollector implements Collector {
  final http.Client _client;
  RssCollector([http.Client? client]) : _client = client ?? http.Client();

  // A normal browser User-Agent. Google News and several trade sites answer a
  // bot-looking agent with HTTP 429 / 401 / 403.
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/rss+xml, application/atom+xml, application/xml, '
        'text/xml;q=0.9, */*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Total tries per source when the server says "slow down" or is briefly
  /// unavailable (HTTP 429 / 502 / 503 / 504).
  static const _maxAttempts = 3;
  static final _random = Random();

  @override
  bool handles(FeedSource source) =>
      source.kind == SourceKind.rss || source.kind == SourceKind.googleAlert;

  /// GET with a polite retry: waits (honouring `Retry-After` when sent) and
  /// tries again on rate-limit / temporary-outage responses.
  Future<http.Response> _get(Uri uri) async {
    late http.Response resp;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      resp = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 25));
      final retryable = resp.statusCode == 429 ||
          resp.statusCode == 502 ||
          resp.statusCode == 503 ||
          resp.statusCode == 504;
      if (!retryable || attempt == _maxAttempts) break;
      await Future<void>.delayed(_retryDelay(resp, attempt));
    }
    return resp;
  }

  static Duration _retryDelay(http.Response resp, int attempt) {
    final retryAfter = int.tryParse(resp.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: min(retryAfter, 60));
    }
    // 8s, then 24s, plus up to 3s of jitter.
    final baseMs = attempt == 1 ? 8000 : 24000;
    return Duration(milliseconds: baseMs + _random.nextInt(3000));
  }

  static String _httpError(int code) => switch (code) {
        429 => 'HTTP 429 (rate limited, will retry next refresh)',
        401 || 403 => 'HTTP $code (site refused the request)',
        404 => 'HTTP 404 (feed address not found)',
        _ => 'HTTP $code',
      };

  @override
  Future<CollectResult> fetch(FeedSource source) async {
    try {
      final resp = await _get(Uri.parse(source.url));

      if (resp.statusCode != 200) {
        return CollectResult.failure(_httpError(resp.statusCode));
      }
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final head = body.trimLeft();
      final probe =
          head.substring(0, min(200, head.length)).toLowerCase();
      if (probe.startsWith('<!doctype html') || probe.startsWith('<html')) {
        return CollectResult.failure(
            'This address is a web page, not an RSS/Atom feed');
      }
      final doc = XmlDocument.parse(body);
      final now = DateTime.now().toUtc().toIso8601String();

      final items = <Lead>[];
      // RSS 2.0
      for (final item in doc.findAllElements('item')) {
        final lead = _fromRss(item, source, now);
        if (lead != null) items.add(lead);
      }
      // Atom
      if (items.isEmpty) {
        for (final entry in doc.findAllElements('entry')) {
          final lead = _fromAtom(entry, source, now);
          if (lead != null) items.add(lead);
        }
      }
      return CollectResult(items);
    } on XmlException {
      return CollectResult.failure('feed is not valid XML');
    } catch (e) {
      return CollectResult.failure(e.toString());
    }
  }

  Lead? _fromRss(XmlElement item, FeedSource source, String now) {
    final link = _text(item, 'link');
    final guid = _text(item, 'guid');
    final raw = link.isNotEmpty
        ? link
        : (guid.startsWith('http') ? guid : '');
    if (raw.isEmpty) return null;
    final url = unwrapUrl(raw);
    final published = _firstNonEmpty([
      _text(item, 'pubDate'),
      _text(item, 'published'),
      _text(item, 'date'),
    ]);
    final rawDesc = _firstNonEmpty([
      _text(item, 'encoded'), // content:encoded
      _text(item, 'description'),
      _text(item, 'summary'),
    ]);
    return Lead(
      urlHash: Lead.hashUrl(url),
      url: url,
      title: _clean(_text(item, 'title')),
      summary: _clean(rawDesc),
      published: published,
      publishedDate: parsePublishedDate(published),
      sourceName: source.name,
      sourceType: source.kind,
      language: source.language,
      country: source.country,
      collectedAt: now,
      imageUrl: _extractImage(item, rawDesc),
    );
  }

  Lead? _fromAtom(XmlElement entry, FeedSource source, String now) {
    // Atom links live in <link href="..."> attributes.
    String url = '';
    for (final l in entry.findElements('link')) {
      final rel = l.getAttribute('rel');
      final href = l.getAttribute('href');
      if (href == null) continue;
      if (rel == null || rel == 'alternate') {
        url = href;
        break;
      }
      url = href;
    }
    if (url.isEmpty) {
      final id = _text(entry, 'id');
      if (id.startsWith('http')) url = id;
    }
    if (url.isEmpty) return null;
    url = unwrapUrl(url);
    final published = _firstNonEmpty([
      _text(entry, 'published'),
      _text(entry, 'updated'),
    ]);
    final rawDesc =
        _firstNonEmpty([_text(entry, 'content'), _text(entry, 'summary')]);
    return Lead(
      urlHash: Lead.hashUrl(url),
      url: url,
      title: _clean(_text(entry, 'title')),
      summary: _clean(rawDesc),
      published: published,
      publishedDate: parsePublishedDate(published),
      sourceName: source.name,
      sourceType: source.kind,
      language: source.language,
      country: source.country,
      collectedAt: now,
      imageUrl: _extractImage(entry, rawDesc),
    );
  }

  static String _text(XmlElement parent, String tag) {
    final el = parent.findElements(tag);
    if (el.isEmpty) return '';
    return el.first.innerText.trim();
  }

  static String _firstNonEmpty(List<String> xs) =>
      xs.firstWhere((x) => x.trim().isNotEmpty, orElse: () => '');

  // Strip tags + decode HTML entities (e.g. &nbsp;, &amp;) and collapse space.
  static String _clean(String s) => cleanHtmlText(s);

  static final _imgTagRe =
      RegExp('<img[^>]+src=["\']([^"\']+)["\']', caseSensitive: false);

  static bool _looksLikeImage(String url) => RegExp(
        r'\.(jpe?g|png|webp|gif|avif)(\?|$)',
        caseSensitive: false,
      ).hasMatch(url);

  /// Best-effort featured image: MRSS media:content / media:thumbnail, an
  /// image enclosure, or the first `<img>` in the description/content HTML.
  static String _extractImage(XmlElement item, String rawDesc) {
    for (final el in item.descendantElements) {
      final local = el.name.local.toLowerCase();
      if (local == 'content' || local == 'thumbnail') {
        final url = el.getAttribute('url');
        final medium =
            (el.getAttribute('medium') ?? el.getAttribute('type') ?? '')
                .toLowerCase();
        if (url != null &&
            (medium.contains('image') || _looksLikeImage(url))) {
          return url.trim();
        }
      } else if (local == 'enclosure') {
        final url = el.getAttribute('url');
        final type = (el.getAttribute('type') ?? '').toLowerCase();
        if (url != null &&
            (type.startsWith('image') || _looksLikeImage(url))) {
          return url.trim();
        }
      }
    }
    final m = _imgTagRe.firstMatch(rawDesc);
    if (m != null) {
      final src = m.group(1)!.trim();
      if (src.startsWith('http')) return src;
    }
    return '';
  }
}
