import 'package:share_plus/share_plus.dart';

import '../data/models/lead.dart';

/// Shares one or more leads as plain text via the OS share sheet.
Future<void> shareLeads(List<Lead> leads) async {
  if (leads.isEmpty) return;

  String block(Lead l) {
    final lines = <String>[
      l.title.isEmpty ? '(no title)' : l.title,
      if (l.company.isNotEmpty) 'Company: ${l.company}',
      if (l.detectedCountry.isNotEmpty) 'Country: ${l.detectedCountry}',
      'Score: ${l.score}/10',
      if (l.url.isNotEmpty) l.url,
    ];
    return lines.join('\n');
  }

  final single = leads.length == 1;
  final body = leads.map(block).join('\n\n');
  final text = single ? body : 'Bastak leads (${leads.length}):\n\n$body';

  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: single ? leads.first.title : 'Bastak leads (${leads.length})',
    ),
  );
}
