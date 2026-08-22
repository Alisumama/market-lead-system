import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/feed_source.dart';
import '../../data/models/lead.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'source_editor.dart';

/// Manage the feed registry: enable/disable, add, edit, delete. Gives the user
/// complete control over what the pipeline collects. Each row shows the health
/// of its last run (the "scrapers break silently" safeguard from the original).
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = state.sources;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, state, null),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            titleSpacing: 20,
            title: const Text('Sources'),
            actions: [
              IconButton(
                tooltip: 'Refresh now',
                onPressed: state.refreshing ? null : () => state.refresh(),
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '${sources.where((s) => s.enabled).length} of ${sources.length} '
                'enabled',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            sliver: SliverList.separated(
              itemCount: sources.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _SourceCard(source: sources[i], state: state),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _edit(
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
        onTap: () => SourcesPage._edit(context, state, source),
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
                    await SourcesPage._edit(context, state, source);
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
