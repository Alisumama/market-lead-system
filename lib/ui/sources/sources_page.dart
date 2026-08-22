import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/feed_source.dart';
import '../../data/models/lead.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_bar_bits.dart';
import '../widgets/format_picker.dart';
import '../widgets/multi_select_sheet.dart';
import 'source_editor.dart';

Future<void> _editSource(
    BuildContext context, AppState state, FeedSource? existing) async {
  final result = await showModalBottomSheet<FeedSource>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (_) => SourceEditor(source: existing),
  );
  if (result != null) await state.saveSource(result);
}

/// Manage the feed registry: enable/disable, add, edit, delete, with search
/// (name/URL) and Type/Country filters. Each row shows the health of its last
/// run (the "scrapers break silently" safeguard from the original).
class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  final Set<String> _types = {}; // SourceKind labels; empty = all
  final Set<String> _countries = {}; // empty = all

  List<FeedSource> _filter(List<FeedSource> all) {
    final q = _search.trim().toLowerCase();
    return all.where((s) {
      if (q.isNotEmpty &&
          !s.name.toLowerCase().contains(q) &&
          !s.url.toLowerCase().contains(q)) {
        return false;
      }
      if (_types.isNotEmpty && !_types.contains(s.kind.label)) return false;
      if (_countries.isNotEmpty && !_countries.contains(s.country)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.sources;
    final filtered = _filter(all);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSource(context, state, null),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: translucentBarColor(context),
            flexibleSpace: frostedFlexibleSpace(),
            leading: mobileBrandLeading(context),
            leadingWidth: 58,
            automaticallyImplyLeading: false,
            titleSpacing: mobileBrandLeading(context) == null ? 20 : 4,
            title: const Text('Sources'),
            actions: [
              IconButton(
                tooltip: 'Import sources',
                onPressed: () => _import(context, state),
                icon: const Icon(Icons.file_upload_outlined),
              ),
              IconButton(
                tooltip: 'Export sources',
                onPressed: filtered.isEmpty
                    ? null
                    : () => _export(context, filtered),
                icon: const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                tooltip: 'Refresh now',
                onPressed: state.refreshing ? null : () => state.refresh(),
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(child: _searchAndFilters(context, all)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '${filtered.where((s) => s.enabled).length} enabled · '
                '${filtered.length} shown of ${all.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('No sources match your filters')),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _SourceCard(source: filtered[i], state: state),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchAndFilters(BuildContext context, List<FeedSource> all) {
    final typeOptions = {for (final s in all) s.kind.label}.toList()..sort();
    final countryOptions = {for (final s in all) s.country}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search name or URL…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      }),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(
                context,
                icon: Icons.category_outlined,
                label: _types.isEmpty
                    ? 'All types'
                    : (_types.length == 1
                        ? _types.first
                        : '${_types.length} types'),
                onTap: () async {
                  final picked = await showModalBottomSheet<Set<String>>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => MultiSelectSheet(
                        title: 'Filter by type',
                        searchHint: 'Search types…',
                        allLabel: 'All types',
                        options: typeOptions,
                        selected: _types),
                  );
                  if (picked != null) {
                    setState(() {
                      _types
                        ..clear()
                        ..addAll(picked);
                    });
                  }
                },
              ),
              _filterChip(
                context,
                icon: Icons.public,
                label: _countries.isEmpty
                    ? 'All countries'
                    : (_countries.length == 1
                        ? _countries.first
                        : '${_countries.length} countries'),
                onTap: () async {
                  final picked = await showModalBottomSheet<Set<String>>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => MultiSelectSheet(
                        title: 'Filter by country',
                        searchHint: 'Search countries…',
                        allLabel: 'All countries',
                        options: countryOptions,
                        selected: _countries),
                  );
                  if (picked != null) {
                    setState(() {
                      _countries
                        ..clear()
                        ..addAll(picked);
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, List<FeedSource> sources) async {
    final choice = await pickExportFormat(context, includeJson: true);
    if (choice == null || !context.mounted) return;
    try {
      final svc = ExportService();
      final path = choice == kExportJson
          ? await svc.exportSourcesJson(sources)
          : await svc.exportSources(sources, choice as ExportFormat);
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported ${sources.length} sources → $path')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _import(BuildContext context, AppState state) async {
    try {
      final imported = await ExportService().importSources();
      if (imported == null || !context.mounted) return;
      final added = await state.importSources(imported);
      if (!context.mounted) return;
      final skipped = imported.length - added;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported $added source(s)'
              '${skipped > 0 ? ' · $skipped already existed' : ''}')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Widget _filterChip(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

class _SourceCard extends StatelessWidget {
  final FeedSource source;
  final AppState state;
  const _SourceCard({required this.source, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = source.lastStatus;
    final (statusColor, statusIcon) = switch (status) {
      'ok' => (AppTheme.brandGreen, Icons.check_circle),
      'error' => (scheme.error, Icons.error),
      _ => (scheme.onSurfaceVariant, Icons.remove_circle_outline),
    };

    return Card(
      child: InkWell(
        onTap: () => _editSource(context, state, source),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(source.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (source.builtIn) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.verified,
                              size: 14, color: scheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(source.url,
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _miniTag(source.kind.label),
                        const SizedBox(width: 6),
                        _miniTag(source.country),
                        const SizedBox(width: 8),
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status == null
                              ? 'not run yet'
                              : '${source.lastNew} new / ${source.lastFound}',
                          style: TextStyle(
                              fontSize: 11, color: statusColor),
                        ),
                      ],
                    ),
                    if (status == 'error' && source.lastError != null) ...[
                      const SizedBox(height: 4),
                      Text(source.lastError!,
                          style: TextStyle(
                              fontSize: 10, color: scheme.error),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              Switch(
                value: source.enabled,
                onChanged: (v) => state.toggleSource(source, v),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await _editSource(context, state, source);
                  } else if (v == 'delete') {
                    final ok = await _confirmDelete(context);
                    if (ok == true) await state.deleteSource(source);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTag(String text) => Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6)),
          child: Text(text, style: const TextStyle(fontSize: 10)),
        );
      });

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete source?'),
        content: Text('Remove "${source.name}" from your registry? '
            'Leads already collected from it are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// Exposed so SourceEditor can reuse the same SourceKind choices.
const editableKinds = [SourceKind.rss, SourceKind.googleAlert];
