import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/lead_repository.dart';
import '../../data/models/lead.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/score_badge.dart';
import 'lead_detail.dart';

class LeadsPage extends StatefulWidget {
  const LeadsPage({super.key});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  final _searchCtrl = TextEditingController();

  Future<void> _export(AppState state) async {
    if (state.leads.isEmpty) return;
    try {
      final path = await ExportService().exportCsv(state.leads);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exported ${state.leads.length} leads → $path'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => state.refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              titleSpacing: 20,
              title: const Text('Leads'),
              actions: [
                IconButton(
                  tooltip: 'Export CSV',
                  onPressed: () => _export(state),
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'Refresh now',
                  onPressed: state.refreshing ? null : () => state.refresh(),
                  icon: state.refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(child: _StatsRow(stats: state.stats)),
            SliverToBoxAdapter(
              child: _SearchAndFilters(
                  state: state, searchCtrl: _searchCtrl),
            ),
            if (state.leads.isEmpty)
              SliverFillRemaining(
                  hasScrollBody: false, child: _EmptyState(state: state))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemCount: state.leads.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) =>
                      _LeadCard(lead: state.leads[i], state: state),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

class _StatsRow extends StatelessWidget {
  final LeadStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Total', stats.total, Icons.inbox_outlined, Colors.blueGrey),
      ('Hot (8+)', stats.hot, Icons.local_fire_department,
          AppTheme.brandGreen),
      ('Warm (4-7)', stats.warm, Icons.trending_up,
          const Color(0xFFE8A317)),
      ('Fresh', stats.fresh, Icons.schedule, Colors.teal),
      ('Starred', stats.favorites, Icons.star, Colors.amber),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (label, value, icon, color) = items[i];
          return Card(
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const Spacer(),
                  Text('$value',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                  Text(label,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  final AppState state;
  final TextEditingController searchCtrl;
  const _SearchAndFilters(
      {required this.state, required this.searchCtrl});

  @override
  Widget build(BuildContext context) {
    final q = state.query;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchCtrl,
            onChanged: state.setSearch,
            decoration: InputDecoration(
              hintText: 'Search title, company, source…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchCtrl.clear();
                        state.setSearch('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _MinScoreChip(state: state),
                const SizedBox(width: 8),
                _CountryChip(state: state),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Fresh only'),
                  selected: q.freshOnly,
                  onSelected: state.toggleFreshOnly,
                  avatar: const Icon(Icons.schedule, size: 16),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Starred'),
                  selected: q.favoritesOnly,
                  onSelected: state.toggleFavoritesOnly,
                  avatar: const Icon(Icons.star, size: 16),
                ),
                const SizedBox(width: 8),
                _SortChip(state: state),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 4),
            child: Text('${state.leads.length} shown',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _MinScoreChip extends StatelessWidget {
  final AppState state;
  const _MinScoreChip({required this.state});
  @override
  Widget build(BuildContext context) {
    final v = state.query.minScore;
    return ActionChip(
      avatar: const Icon(Icons.filter_alt_outlined, size: 16),
      label: Text(v == 0 ? 'Any score' : 'Score ≥ $v'),
      onPressed: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (_) => _ScorePickerSheet(current: v),
        );
        if (picked != null) state.setMinScore(picked);
      },
    );
  }
}

class _ScorePickerSheet extends StatefulWidget {
  final int current;
  const _ScorePickerSheet({required this.current});
  @override
  State<_ScorePickerSheet> createState() => _ScorePickerSheetState();
}

class _ScorePickerSheetState extends State<_ScorePickerSheet> {
  late double _v = widget.current.toDouble();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Minimum score: ${_v.round()}',
              style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _v,
            min: 0,
            max: 10,
            divisions: 10,
            label: '${_v.round()}',
            onChanged: (x) => setState(() => _v = x),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _v.round()),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  final AppState state;
  const _CountryChip({required this.state});
  @override
  Widget build(BuildContext context) {
    final selected = state.query.country;
    return ActionChip(
      avatar: const Icon(Icons.public, size: 16),
      label: Text(selected == null || selected.isEmpty
          ? 'All countries'
          : selected),
      onPressed: () async {
        final picked = await showModalBottomSheet<String?>(
          context: context,
          builder: (_) => _CountryPickerSheet(
              countries: state.countries, current: selected),
        );
        // Distinguish "cleared" from "dismissed" via a sentinel.
        if (picked == '__all__') {
          state.setCountry(null);
        } else if (picked != null) {
          state.setCountry(picked);
        }
      },
    );
  }
}

class _CountryPickerSheet extends StatelessWidget {
  final List<String> countries;
  final String? current;
  const _CountryPickerSheet(
      {required this.countries, required this.current});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('All countries'),
            trailing: current == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, '__all__'),
          ),
          const Divider(height: 1),
          for (final c in countries)
            ListTile(
              title: Text(c),
              trailing: current == c ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final AppState state;
  const _SortChip({required this.state});
  @override
  Widget build(BuildContext context) {
    String label(LeadSort s) => switch (s) {
          LeadSort.scoreDesc => 'Top score',
          LeadSort.dateDesc => 'Newest',
          LeadSort.dateAsc => 'Oldest',
          LeadSort.titleAsc => 'A–Z',
        };
    return PopupMenuButton<LeadSort>(
      initialValue: state.query.sort,
      onSelected: state.setSort,
      itemBuilder: (_) => [
        for (final s in LeadSort.values)
          PopupMenuItem(value: s, child: Text(label(s))),
      ],
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(label(state.query.sort)),
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final AppState state;
  const _LeadCard({required this.lead, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = <String>[
      if (lead.company.isNotEmpty) lead.company,
      if (lead.detectedCountry.isNotEmpty)
        lead.detectedCountry
      else if (lead.country.isNotEmpty && lead.country != 'global')
        lead.country,
      if (lead.publishedDate.isNotEmpty) lead.publishedDate,
    ];
    return Card(
      child: InkWell(
        onTap: () => showLeadDetail(context, lead, state),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScoreBadge(lead.score),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.title.isEmpty ? '(no title)' : lead.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(meta.join('  •  '),
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _tag(context, lead.sourceType.label,
                            Icons.rss_feed, scheme.surfaceContainerHighest),
                        if (lead.projectType.isNotEmpty)
                          _tag(context, lead.projectType,
                              Icons.category_outlined,
                              scheme.primary.withValues(alpha: 0.12)),
                        _StatusPill(status: lead.status),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => state.toggleFavorite(lead),
                icon: Icon(
                  lead.favorite ? Icons.star : Icons.star_border,
                  color: lead.favorite ? Colors.amber : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String text, IconData icon, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11)),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final LeadStatus status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      LeadStatus.fresh => Colors.blue,
      LeadStatus.reviewing => Colors.orange,
      LeadStatus.contacted => Colors.purple,
      LeadStatus.won => AppTheme.brandGreen,
      LeadStatus.lost => Colors.red,
      LeadStatus.archived => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8)),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppState state;
  const _EmptyState({required this.state});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore,
                size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No leads yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh, or tap Refresh to scan your sources for the\n'
              'first time. New mill / grain / tender leads will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: state.refreshing ? null : () => state.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Scan sources now'),
            ),
          ],
        ),
      ),
    );
  }
}
