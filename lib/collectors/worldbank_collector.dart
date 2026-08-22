import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/feed_source.dart';
import '../data/models/lead.dart';
import 'collector.dart';

/// World Bank procurement-notices collector — actual tenders/bids, the
/// highest-quality lead type. Pure-Dart port of
/// collect_worldbank_procurement.py. Queries a fixed set of target markets and
/// stores each notice as a Lead.
class WorldBankCollector implements Collector {
  final http.Client _client;
  WorldBankCollector([http.Client? client])
      : _client = client ?? http.Client();

  static const _userAgent =
      'BastakLeads/1.0 (+bastakinstruments@gmail.com)';
  static const _detailUrl =
      'https://projects.worldbank.org/en/projects-operations/procurement-detail/';
  static const _rows = 40;

  static const _qterm =
      '"flour mill" OR "flour milling" OR milling OR flour OR "grain mill" OR '
      '"grain milling" OR "grain silo" OR "grain storage" OR "wheat mill"';

  // (project_ctry_name expected by the API, our country tag)
  static const _countries = [
    ['Pakistan', 'pk'],
    ['Nigeria', 'ng'],
    ['Kenya', 'ke'],
    ['Egypt, Arab Republic of', 'eg'],
    ['Ethiopia', 'et'],
    ['Tanzania', 'tz'],
    ['Uganda', 'ug'],
    ['Mozambique', 'mz'],
    ['Kazakhstan', 'kz'],
  ];

  @override
  bool handles(FeedSource source) => source.kind == SourceKind.worldBank;

  @override
  Future<CollectResult> fetch(FeedSource source) async {
    final items = <Lead>[];
    final errors = <String>[];
    final now = DateTime.now().toUtc().toIso8601String();

    for (final c in _countries) {
      try {
        final uri = Uri.parse(source.url).replace(queryParameters: {
          'format': 'json',
          'rows': '$_rows',
          'qterm': _qterm,
          'project_ctry_name_exact': c[0],
        });
        final resp = await _client.get(uri, headers: {
          'User-Agent': _userAgent,
        }).timeout(const Duration(seconds: 45));
        if (resp.statusCode != 200) {
          errors.add('${c[1]}:HTTP ${resp.statusCode}');
          continue;
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final notices = (data['procnotices'] as List?) ?? const [];
        for (final raw in notices) {
          final n = raw as Map<String, dynamic>;
          final lead = _fromNotice(n, c[1], now);
          if (lead != null) items.add(lead);
        }
      } catch (e) {
        errors.add('${c[1]}:$e');
      }
    }

    if (items.isEmpty && errors.isNotEmpty) {
      return CollectResult.failure(errors.join('; '));
    }
    return CollectResult(items,
        status: errors.isEmpty ? 'ok' : 'ok',
        error: errors.isEmpty ? null : errors.join('; '));
  }

  Lead? _fromNotice(Map<String, dynamic> n, String code, String now) {
    final id = (n['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return null;
    final link = '$_detailUrl$id';
    final title = _s(n['bid_description']).isNotEmpty
        ? _s(n['bid_description'])
        : _s(n['project_name']);
    final ntype = _s(n['notice_type']);
    final method = _s(n['procurement_method_name']);
    final proj = _s(n['project_name']);
    final body = _stripHtml(_s(n['notice_text']));
    var summary = [ntype, method, proj].where((x) => x.isNotEmpty).join(' · ');
    if (body.isNotEmpty) {
      final b = body.length > 400 ? body.substring(0, 400) : body;
      summary = summary.isEmpty ? b : '$summary — $b';
    }
    final noticeDate = _s(n['noticedate']);
    return Lead(
      urlHash: Lead.hashUrl(link),
      url: link,
      title: title,
      summary: summary,
      published: noticeDate,
      publishedDate: _parseNoticeDate(noticeDate),
      sourceName: 'World Bank Procurement Notices',
      sourceType: SourceKind.worldBank,
      language: _s(n['notice_lang_name']).isEmpty
          ? 'en'
          : _s(n['notice_lang_name']),
      country: code,
      collectedAt: now,
    );
  }

  static String _s(Object? v) => (v as String?)?.trim() ?? '';

  static final _tagRe = RegExp(r'<[^>]+>');
  static final _wsRe = RegExp(r'\s+');
  static String _stripHtml(String s) =>
      s.replaceAll(_tagRe, ' ').replaceAll(_wsRe, ' ').trim();

  static const _mon = {
    'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04', 'may': '05',
    'jun': '06', 'jul': '07', 'aug': '08', 'sep': '09', 'oct': '10',
    'nov': '11', 'dec': '12',
  };

  // '02-Jun-2026' -> '2026-06-02'
  static String _parseNoticeDate(String raw) {
    final m = RegExp(r'(\d{1,2})-([A-Za-z]{3})-(\d{4})').firstMatch(raw);
    if (m == null) return '';
    final mm = _mon[m.group(2)!.toLowerCase()];
    if (mm == null) return '';
    return '${m.group(3)}-$mm-${m.group(1)!.padLeft(2, '0')}';
  }
}
