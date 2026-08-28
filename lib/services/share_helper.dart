import 'package:share_plus/share_plus.dart';

import '../data/models/lead.dart';

/// Shares one or more leads as plain text via the OS share sheet. A lead's
/// notes are included when it has any, so the context someone recorded against
/// a lead travels with it.
Future<void> shareLeads(List<Lead> leads) async {
  if (leads.isEmpty) return;

  String block(Lead l) {
    final notes = l.notes.trim();
    final lines = <String>[
      l.title.isEmpty ? '(no title)' : l.title,
      if (l.company.isNotEmpty) 'Company: ${l.company}',
      if (l.detectedCountry.isNotEmpty) 'Country: ${l.detectedCountry}',
      'Score: ${l.score}/10',
      if (l.url.isNotEmpty) l.url,
      // Last, after the link: notes are free-form and may run to several lines,
      // so trailing them keeps each block's fixed fields easy to scan.
      if (notes.isNotEmpty) 'Notes: $notes',
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
