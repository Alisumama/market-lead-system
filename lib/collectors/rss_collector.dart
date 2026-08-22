import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../data/models/feed_source.dart';
import '../data/models/lead.dart';
import 'collector.dart';
import 'date_utils.dart';

/// Fetches RSS 2.0 and Atom feeds and turns each entry into a [Lead].
/// Pure-Dart replacement for feedparser + collect.py.
class RssCollector implements Collector {
  final http.Client _client;
  RssCollector([http.Client? client]) : _client = client ?? http.Client();

  static const _userAgent =
      'BastakLeads/1.0 (+contact: bastakinstruments@gmail.com)';

  @override
  bool handles(FeedSource source) =>
      source.kind == SourceKind.rss || source.kind == SourceKind.googleAlert;

  @override
  Future<CollectResult> fetch(FeedSource source) async {
    try {
      final resp = await _client.get(
        Uri.parse(source.url),
        headers: {'User-Agent': _userAgent, 'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml'},
      ).timeout(const Duration(seconds: 25));

      if (resp.statusCode != 200) {
        return CollectResult.failure('HTTP ${resp.statusCode}');
      }
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
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
    } on XmlParserException {
      return CollectResult.failure('feed is not valid XML');
    } catch (e) {
      return CollectResult.failure(e.toString());
    }
  }

  Lead? _fromRss(XmlElement item, FeedSource source, String now) {
    final link = _text(item, 'link');
    final guid = _text(item, 'guid');
    final url = link.isNotEmpty
        ? link
        : (guid.startsWith('http') ? guid : '');
    if (url.isEmpty) return null;
    final published = _firstNonEmpty([
      _text(item, 'pubDate'),
      _text(item, 'published'),
      _text(item, 'date'),
    ]);
    return Lead(
      urlHash: Lead.hashUrl(url),
      url: url,
      title: _clean(_text(item, 'title')),
      summary: _clean(_firstNonEmpty(
          [_text(item, 'description'), _text(item, 'summary')])),
      published: published,
      publishedDate: parsePublishedDate(published),
      sourceName: source.name,
      sourceType: source.kind,
      language: source.language,
      country: source.country,
      collectedAt: now,
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
    final published = _firstNonEmpty([
      _text(entry, 'published'),
      _text(entry, 'updated'),
    ]);
    return Lead(
      urlHash: Lead.hashUrl(url),
      url: url,
      title: _clean(_text(entry, 'title')),
      summary: _clean(_firstNonEmpty(
          [_text(entry, 'summary'), _text(entry, 'content')])),
      published: published,
      publishedDate: parsePublishedDate(published),
      sourceName: source.name,
      sourceType: source.kind,
      language: source.language,
      country: source.country,
      collectedAt: now,
    );
  }

  static String _text(XmlElement parent, String tag) {
    final el = parent.findElements(tag);
    if (el.isEmpty) return '';
    return el.first.innerText.trim();
  }

  static String _firstNonEmpty(List<String> xs) =>
      xs.firstWhere((x) => x.trim().isNotEmpty, orElse: () => '');

  static final _tagRe = RegExp(r'<[^>]+>');
  static final _wsRe = RegExp(r'\s+');
  static String _clean(String s) =>
      s.replaceAll(_tagRe, ' ').replaceAll(_wsRe, ' ').trim();
}
