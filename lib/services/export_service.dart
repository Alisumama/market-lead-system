import 'dart:convert';

import '../data/models/feed_source.dart';
import '../data/models/lead.dart';
import '../scoring/keyword_scorer.dart';
import '../util/text.dart';
import 'exporter.dart';
import 'file_service.dart';

export 'exporter.dart' show ExportFormat, ExportFormatX;

/// Builds and saves lead/source exports (CSV, decorated XLSX, branded PDF) and
/// imports shared source files (JSON/CSV). Saving uses a native dialog on
/// desktop and the storage framework on mobile via [FileService].
class ExportService {
  final FileService _fs = FileService();

  String _stamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .substring(0, 19);

  String _band(int s) => s >= 8 ? 'Hot' : (s >= 4 ? 'Warm' : 'Cold');

  // ---------------- Leads ----------------

  static const _leadHeadersFull = [
    'Published', 'Found', 'Score', 'Band', 'Status', 'Company', 'Country',
    'Detected Country', 'Project Type', 'Title', 'Summary', 'Source',
    'Source Type', 'URL', 'Favorite', 'Notes',
  ];

  List<String> _leadRowFull(Lead l) => [
        l.publishedDate,
        l.collectedAt.length >= 10 ? l.collectedAt.substring(0, 10) : '',
        '${l.score}',
        _band(l.score),
        l.status.label,
        l.company,
        l.country,
        l.detectedCountry,
        l.projectType,
        l.title,
        cleanHtmlText(l.summary),
        l.sourceName,
        l.sourceType.label,
        l.url,
        l.favorite ? 'yes' : 'no',
        l.notes,
      ];

  static const _leadHeadersPdf = [
    'Score', 'Title', 'Company', 'Country', 'Project', 'Status', 'Published',
    'Source',
  ];

  List<String> _leadRowPdf(Lead l) => [
        '${l.score}',
        l.title,
        l.company,
        l.detectedCountry.isNotEmpty ? l.detectedCountry : l.country,
        l.projectType,
        l.status.label,
        l.publishedDate,
        l.sourceName,
      ];

  Future<String?> exportLeads(List<Lead> leads, ExportFormat fmt) async {
    final List<int> bytes;
    switch (fmt) {
      case ExportFormat.csv:
        bytes = Exporter.csv(
            _leadHeadersFull, leads.map(_leadRowFull).toList());
      case ExportFormat.xlsx:
        bytes = Exporter.xlsx(
            'Leads', _leadHeadersFull, leads.map(_leadRowFull).toList());
      case ExportFormat.pdf:
        bytes = await Exporter.pdf(
          title: 'Bastak Leads',
          subtitle: '${leads.length} leads · exported ${_stamp()}',
          headers: _leadHeadersPdf,
          rows: leads.map(_leadRowPdf).toList(),
        );
    }
    return _fs.save(
        fileName: 'bastak_leads_${_stamp()}.${fmt.ext}',
        bytes: bytes,
        ext: fmt.ext);
  }

  // ---------------- Sources ----------------

  static const _sourceHeadersFull = [
    'Name', 'URL', 'Type', 'Language', 'Country', 'Enabled', 'Last status',
    'Last new', 'Last found', 'Last run',
  ];

  List<String> _sourceRowFull(FeedSource s) => [
        s.name,
        s.url,
        s.kind.label,
        s.language,
        s.country,
        s.enabled ? 'yes' : 'no',
        s.lastStatus ?? '',
        '${s.lastNew}',
        '${s.lastFound}',
        s.lastRunAt ?? '',
      ];

  static const _sourceHeadersPdf = [
    'Name', 'Type', 'Country', 'Enabled', 'Last status', 'Last new',
  ];

  List<String> _sourceRowPdf(FeedSource s) => [
        s.name,
        s.kind.label,
        s.country,
        s.enabled ? 'yes' : 'no',
        s.lastStatus ?? '',
        '${s.lastNew}',
      ];

  Future<String?> exportSources(
      List<FeedSource> sources, ExportFormat fmt) async {
    final List<int> bytes;
    switch (fmt) {
      case ExportFormat.csv:
        bytes = Exporter.csv(
            _sourceHeadersFull, sources.map(_sourceRowFull).toList());
      case ExportFormat.xlsx:
        bytes = Exporter.xlsx('Sources', _sourceHeadersFull,
            sources.map(_sourceRowFull).toList());
      case ExportFormat.pdf:
        bytes = await Exporter.pdf(
          title: 'Bastak Sources',
          subtitle: '${sources.length} sources · exported ${_stamp()}',
          headers: _sourceHeadersPdf,
          rows: sources.map(_sourceRowPdf).toList(),
        );
    }
    return _fs.save(
        fileName: 'bastak_sources_${_stamp()}.${fmt.ext}',
        bytes: bytes,
        ext: fmt.ext);
  }

  /// Exports the source registry as a portable JSON file for sharing/importing.
  Future<String?> exportSourcesJson(List<FeedSource> sources) async {
    final data = {
      'app': 'bastak_leads',
      'kind': 'sources',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sources': [
        for (final s in sources)
          {
            'name': s.name,
            'url': s.url,
            'kind': s.kind.storageValue,
            'language': s.language,
            'country': s.country,
            'enabled': s.enabled,
          }
      ],
    };
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    return _fs.save(
        fileName: 'bastak_sources_${_stamp()}.json', bytes: bytes, ext: 'json');
  }

  // ---------------- Scoring / rules config ----------------

  Future<String?> exportScoringConfig(ScoringConfig c) async {
    final data = {
      'app': 'bastak_leads',
      'kind': 'rules',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'config': c.toJson(),
    };
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    return _fs.save(
        fileName: 'bastak_rules_${_stamp()}.json', bytes: bytes, ext: 'json');
  }

  /// Opens a shared rules file (.json) and parses it. Returns null if cancelled.
  Future<ScoringConfig?> importScoringConfig() async {
    final picked = await _fs.open(['json']);
    if (picked == null) return null;
    final data = jsonDecode(utf8.decode(picked.bytes, allowMalformed: true));
    final cfg = (data is Map && data['config'] is Map) ? data['config'] : data;
    return ScoringConfig.fromJson((cfg as Map).cast<String, dynamic>());
  }

  /// Generic text export (used by the Reports digest).
  Future<String?> exportText(String content, String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'txt';
    return _fs.save(fileName: fileName, bytes: utf8.encode(content), ext: ext);
  }

  // ---------------- Import (sources) ----------------

  /// Opens a picker for a shared sources file (.json / .csv) and parses it into
  /// FeedSource objects. Returns null if the user cancelled.
  Future<List<FeedSource>?> importSources() async {
    final picked = await _fs.open(['json', 'csv']);
    if (picked == null) return null;
    final text = utf8.decode(picked.bytes, allowMalformed: true);
    if (picked.name.toLowerCase().endsWith('.csv')) {
      return _parseSourcesCsv(text);
    }
    return _parseSourcesJson(text);
  }

  List<FeedSource> _parseSourcesJson(String text) {
    final data = jsonDecode(text);
    final list = (data is Map ? data['sources'] : data) as List? ?? const [];
    final out = <FeedSource>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final url = (raw['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) continue;
      out.add(FeedSource(
        name: (raw['name'] as String?)?.trim() ?? url,
        url: url,
        kind: SourceKindX.fromStorage(raw['kind'] as String?),
        language: (raw['language'] as String?)?.trim() ?? 'en',
        country: (raw['country'] as String?)?.trim() ?? 'global',
        enabled: raw['enabled'] == true || raw['enabled'] == 'yes',
      ));
    }
    return out;
  }

  List<FeedSource> _parseSourcesCsv(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return [];
    final header = _csvLine(lines.first).map((h) => h.toLowerCase()).toList();
    int col(String name) => header.indexWhere((h) => h.contains(name));
    final iName = col('name'),
        iUrl = col('url'),
        iType = col('type'),
        iLang = col('lang'),
        iCountry = col('country'),
        iEnabled = col('enabled');
    final out = <FeedSource>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final f = _csvLine(line);
      String at(int i) => (i >= 0 && i < f.length) ? f[i] : '';
      final url = at(iUrl).trim();
      if (url.isEmpty) continue;
      out.add(FeedSource(
        name: at(iName).trim().isEmpty ? url : at(iName).trim(),
        url: url,
        kind: _kindFromLabel(at(iType)),
        language: at(iLang).trim().isEmpty ? 'en' : at(iLang).trim(),
        country: at(iCountry).trim().isEmpty ? 'global' : at(iCountry).trim(),
        enabled: at(iEnabled).toLowerCase().trim() == 'yes' ||
            at(iEnabled).toLowerCase().trim() == 'true',
      ));
    }
    return out;
  }

  SourceKind _kindFromLabel(String v) {
    final s = v.toLowerCase();
    if (s.contains('google')) return SourceKind.googleAlert;
    if (s.contains('world')) return SourceKind.worldBank;
    if (s.contains('manual')) return SourceKind.manual;
    return SourceKind.rss;
  }

  /// Minimal RFC-4180-ish CSV line parser (handles quoted fields with commas).
  List<String> _csvLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    return out;
  }
}
