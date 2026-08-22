import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/lead.dart';

/// Exports leads to a CSV file the user fully owns. On desktop it writes to the
/// Downloads/Documents folder and returns the path; on mobile it opens the
/// share sheet so the user can save it wherever they like.
class ExportService {
  static const _headers = [
    'Published',
    'Found',
    'Score',
    'Band',
    'Status',
    'Company',
    'Country',
    'Detected Country',
    'Project Type',
    'Title',
    'Summary',
    'Source',
    'Source Type',
    'URL',
    'Favorite',
    'Notes',
  ];

  Future<String> exportCsv(List<Lead> leads) async {
    final buf = StringBuffer()..writeln(_headers.map(_esc).join(','));
    for (final l in leads) {
      buf.writeln([
        l.publishedDate,
        l.collectedAt.length >= 10 ? l.collectedAt.substring(0, 10) : '',
        l.score,
        _band(l.score),
        l.status.label,
        l.company,
        l.country,
        l.detectedCountry,
        l.projectType,
        l.title,
        l.summary,
        l.sourceName,
        l.sourceType.label,
        l.url,
        l.favorite ? 'yes' : 'no',
        l.notes,
      ].map(_esc).join(','));
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final fileName = 'bastak_leads_$stamp.csv';

    final dir = await _outputDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buf.toString());

    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Bastak leads export'),
      );
    }
    return file.path;
  }

  Future<Directory> _outputDir() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  static String _band(int s) =>
      s >= 8 ? 'Hot' : (s >= 4 ? 'Warm' : 'Cold');

  static String _esc(Object? v) {
    var s = (v ?? '').toString().replaceAll('"', '""');
    if (s.contains(',') || s.contains('\n') || s.contains('"')) {
      s = '"$s"';
    }
    return s;
  }
}
