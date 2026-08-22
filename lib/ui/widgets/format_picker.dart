import 'package:flutter/material.dart';

import '../../services/exporter.dart';

/// A special sentinel value returned by the picker for the shareable JSON
/// option (only offered when [includeJson] is true).
const String kExportJson = 'json';

/// Shows a bottom sheet to choose an export format. Returns the chosen
/// [ExportFormat], the string [kExportJson], or null if dismissed.
Future<Object?> pickExportFormat(BuildContext context,
    {bool includeJson = false}) {
  return showModalBottomSheet<Object?>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Export as',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('CSV'),
            subtitle: const Text('Plain spreadsheet, opens anywhere'),
            onTap: () => Navigator.pop(context, ExportFormat.csv),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Excel (.xlsx)'),
            subtitle: const Text('Styled table with branded header'),
            onTap: () => Navigator.pop(context, ExportFormat.xlsx),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Branded, print-ready report'),
            onTap: () => Navigator.pop(context, ExportFormat.pdf),
          ),
          if (includeJson)
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Shareable file (.json)'),
              subtitle: const Text('For importing into another device'),
              onTap: () => Navigator.pop(context, kExportJson),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
