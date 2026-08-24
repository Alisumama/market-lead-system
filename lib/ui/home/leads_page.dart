import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/lead_repository.dart';
import '../../data/models/lead.dart';
import '../../services/export_service.dart';
import '../../services/share_helper.dart';
import '../../state/app_state.dart';
import '../widgets/format_picker.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_bar_bits.dart';
import '../widgets/lead_image.dart';
import '../widgets/score_badge.dart';
import 'lead_detail.dart';

class LeadsPage extends StatefulWidget {
  const LeadsPage({super.key});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  final _searchCtrl = TextEditingController();
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  List<Lead> _selectedLeads(AppState state) => state.leads.where((l) => l.id != null && _selected.contains(l.id)).toList();

  void _toggle(Lead lead) {
    if (lead.id == null) return;
    setState(() {
      if (!_selected.remove(lead.id)) _selected.add(lead.id!);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAll(AppState state) => setState(() {
    _selected
      ..clear()
      ..addAll(state.leads.map((l) => l.id).whereType<int>());
  });

  Future<void> _exportLeads(List<Lead> leads) async {
    if (leads.isEmpty) return;
    final fmt = await pickExportFormat(context);
    if (fmt is! ExportFormat || !mounted) return;
    try {
      final path = await ExportService().exportLeads(leads, fmt);
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${leads.length} leads → $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _bulkDelete(AppState state) async {
    final leads = _selectedLeads(state);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${leads.length} leads?'),
        content: const Text('This removes them from your local database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.deleteMany(leads);
      _clearSelection();
    }
  }

  Future<void> _bulkStatus(AppState state, LeadStatus status) async {
    await state.setStatusMany(_selectedLeads(state), status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved ${_selected.length} to ${status.label}')));
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final scroll = CustomScrollView(
          slivers: [
            if (_selecting) _selectionAppBar(state) else _normalAppBar(state),
            SliverToBoxAdapter(child: _StatsRow(stats: state.stats)),
            SliverToBoxAdapter(
              child: _SearchAndFilters(state: state, searchCtrl: _searchCtrl),
            ),
            if (state.leads.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _EmptyState(state: state))
            else if (state.leadView == LeadView.grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 178,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final lead = state.leads[i];
                      return _LeadGridCard(
                        lead: lead,
                        state: state,
                        selecting: _selecting,
                        selected: _selected.contains(lead.id),
                        onToggleSelect: () => _toggle(lead),
                      );
                    },
                    childCount: state.leads.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemCount: state.leads.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 5),
                  itemBuilder: (context, i) {
                    final lead = state.leads[i];
                    return _LeadCard(lead: lead, state: state, selecting: _selecting, selected: _selected.contains(lead.id), onToggleSelect: () => _toggle(lead));
                  },
                ),
              ),
          ],
        );
    // Pull-to-refresh only makes sense on touch (Android); desktop uses the
    // Refresh button instead.
    final mobile = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      body: mobile
          ? RefreshIndicator(onRefresh: () => state.refresh(), child: scroll)
          : scroll,
    );
  }

  Widget _normalAppBar(AppState state) => SliverAppBar(
    floating: true,
    backgroundColor: translucentBarColor(context),
    flexibleSpace: frostedFlexibleSpace(),
    leading: mobileBrandLeading(context),
    leadingWidth: 58,
    automaticallyImplyLeading: false,
    titleSpacing: mobileBrandLeading(context) == null ? 20 : 4,
    title: const Text('Leads'),
    actions: [
      IconButton(
        tooltip: state.leadView == LeadView.grid
            ? 'List view'
            : 'Grid view',
        onPressed: () => state.setLeadView(
            state.leadView == LeadView.grid ? LeadView.list : LeadView.grid),
        icon: Icon(state.leadView == LeadView.grid
            ? Icons.view_agenda_outlined
            : Icons.grid_view_outlined),
      ),
      IconButton(tooltip: 'Export CSV', onPressed: () => _exportLeads(state.leads), icon: const Icon(Icons.download_outlined)),
      IconButton(
        tooltip: 'Refresh now',
        onPressed: state.refreshing ? null : () => state.refresh(),
        icon: state.refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
      ),
      const SizedBox(width: 8),
    ],
  );

  Widget _selectionAppBar(AppState state) => SliverAppBar(
    floating: true,
    pinned: true,
    backgroundColor: translucentBarColor(context),
    flexibleSpace: frostedFlexibleSpace(),
    titleSpacing: 8,
    leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection, tooltip: 'Clear selection'),
    title: Text('${_selected.length} selected'),
    actions: [
      IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: () => _selectAll(state)),
      PopupMenuButton<LeadStatus>(
        tooltip: 'Set status',
        icon: const Icon(Icons.label_outline),
        onSelected: (s) => _bulkStatus(state, s),
        itemBuilder: (_) => [for (final s in LeadStatus.values) PopupMenuItem(value: s, child: Text('Move to ${s.label}'))],
      ),
      IconButton(tooltip: 'Share selected', icon: const Icon(Icons.share_outlined), onPressed: () => shareLeads(_selectedLeads(state))),
      IconButton(tooltip: 'Export selected', icon: const Icon(Icons.download_outlined), onPressed: () => _exportLeads(_selectedLeads(state))),
      IconButton(tooltip: 'Delete selected', icon: const Icon(Icons.delete_outline), onPressed: () => _bulkDelete(state)),
      const SizedBox(width: 4),
    ],
  );

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
      ('Hot (8+)', stats.hot, Icons.local_fire_department, AppTheme.brandGreen),
      ('Warm (4-7)', stats.warm, Icons.trending_up, const Color(0xFFE8A317)),
      ('Fresh', stats.fresh, Icons.schedule, Colors.teal),
      ('Starred', stats.favorites, Icons.star, Colors.amber),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;

    // Desktop: a single content-sized row (all five fit comfortably).
    if (wide) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _StatCard(
                  label: items[i].$1,
                  value: items[i].$2,
                  icon: items[i].$3,
                  color: items[i].$4),
            ],
          ],
        ),
      );
    }

    // Mobile: a tidy 3-per-row grid (5 cards -> two rows), cards sized to fill
    // the width evenly with small gaps.
    const gap = 8.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: LayoutBuilder(
        builder: (context, c) {
          final cardW = (c.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final it in items)
                _StatCard(
                    label: it.$1,
                    value: it.$2,
                    icon: it.$3,
                    color: it.$4,
                    width: cardW),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final double? width; // null -> content width (desktop row)
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.width});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        width: width ?? 116,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text('$value',
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 1),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  final AppState state;
  final TextEditingController searchCtrl;
  const _SearchAndFilters({required this.state, required this.searchCtrl});

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
          Builder(builder: (context) {
            final chips = <Widget>[
              _MinScoreChip(state: state),
              _CountryChip(state: state),
              _SourceChip(state: state),
              _StatusChip(state: state),
              _DateRangeChip(state: state),
              FilterChip(
                  label: const Text('Fresh only'),
                  selected: q.freshOnly,
                  onSelected: state.toggleFreshOnly,
                  avatar: const Icon(Icons.schedule, size: 16)),
              FilterChip(
                  label: const Text('Starred'),
                  selected: q.favoritesOnly,
                  onSelected: state.toggleFavoritesOnly,
                  avatar: const Icon(Icons.star, size: 16)),
              _SortChip(state: state),
            ];
            // Desktop: wrap chips onto new lines when the width is tight.
            // Mobile: keep a single horizontally-scrolling row.
            final wide = MediaQuery.sizeOf(context).width >= 800;
            if (wide) {
              return Wrap(spacing: 8, runSpacing: 8, children: chips);
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chips[i],
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 4),
            child: Text('${state.leads.length} shown', style: Theme.of(context).textTheme.bodySmall),
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
    final maxV = state.query.maxScore;
    final label = maxV < 10
        ? 'Score $v–$maxV'
        : (v == 0 ? 'Any score' : 'Score ≥ $v');
    return ActionChip(
      avatar: const Icon(Icons.filter_alt_outlined, size: 16),
      label: Text(label),
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
          Text('Minimum score: ${_v.round()}', style: Theme.of(context).textTheme.titleMedium),
          Slider(value: _v, min: 0, max: 10, divisions: 10, label: '${_v.round()}', onChanged: (x) => setState(() => _v = x)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: () => Navigator.pop(context, _v.round()), child: const Text('Apply')),
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
    final selected = state.query.countries;
    final label = switch (selected.length) {
      0 => 'All countries',
      1 => selected.first,
      _ => '${selected.length} countries',
    };
    return ActionChip(
      avatar: const Icon(Icons.public, size: 16),
      label: Text(label),
      onPressed: () async {
        final picked = await showModalBottomSheet<Set<String>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _MultiSelectSheet(
            title: 'Filter by country',
            searchHint: 'Search countries…',
            allLabel: 'All countries',
            options: state.countries,
            selected: selected,
          ),
        );
        if (picked != null) state.setCountries(picked);
      },
    );
  }
}

class _SourceChip extends StatelessWidget {
  final AppState state;
  const _SourceChip({required this.state});
  @override
  Widget build(BuildContext context) {
    final selected = state.query.sourceNames;
    final label = switch (selected.length) {
      0 => 'All sources',
      1 => selected.first,
      _ => '${selected.length} sources',
    };
    return ActionChip(
      avatar: const Icon(Icons.rss_feed, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      onPressed: () async {
        final picked = await showModalBottomSheet<Set<String>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _MultiSelectSheet(
            title: 'Filter by source',
            searchHint: 'Search sources…',
            allLabel: 'All sources',
            options: state.sourceNames,
            selected: selected,
          ),
        );
        if (picked != null) state.setSourceNames(picked);
      },
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  final AppState state;
  const _DateRangeChip({required this.state});

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _pretty(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[d.month - 1]} ${d.day}';
  }

  Future<void> _pick(BuildContext context) async {
    final q = state.query;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange? initial;
    if (q.dateFrom.isNotEmpty && q.dateTo.isNotEmpty) {
      final s = DateTime.tryParse(q.dateFrom);
      final e = DateTime.tryParse(q.dateTo);
      if (s != null && e != null) initial = DateTimeRange(start: s, end: e);
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: today,
      initialDateRange: initial,
    );
    if (picked != null) {
      state.setDateRange(_fmt(picked.start), _fmt(picked.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = state.query;
    if (q.hasDateRange) {
      final label = '${_pretty(q.dateFrom)} – ${_pretty(q.dateTo)}';
      return InputChip(
        avatar: const Icon(Icons.event, size: 16),
        label: Text(label),
        onPressed: () => _pick(context),
        onDeleted: () => state.setDateRange('', ''),
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.event_outlined, size: 16),
      label: const Text('Any date'),
      onPressed: () => _pick(context),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AppState state;
  const _StatusChip({required this.state});
  @override
  Widget build(BuildContext context) {
    final selected = state.query.statuses;
    final label = switch (selected.length) {
      0 => 'Any status',
      1 => selected.first.label,
      _ => '${selected.length} statuses',
    };
    return ActionChip(
      avatar: const Icon(Icons.flag_outlined, size: 16),
      label: Text(label),
      onPressed: () async {
        final picked = await showModalBottomSheet<Set<LeadStatus>>(
          context: context,
          showDragHandle: true,
          builder: (_) => _StatusPickerSheet(selected: selected),
        );
        if (picked != null) state.setStatusFilter(picked);
      },
    );
  }
}

class _StatusPickerSheet extends StatefulWidget {
  final Set<LeadStatus> selected;
  const _StatusPickerSheet({required this.selected});
  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  late final Set<LeadStatus> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text('Filter by status',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_sel.isNotEmpty)
                  TextButton(
                      onPressed: () => setState(_sel.clear),
                      child: const Text('Clear')),
              ],
            ),
          ),
          for (final s in LeadStatus.values)
            CheckboxListTile(
              dense: true,
              value: _sel.contains(s),
              title: Text(s.label),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (_) => setState(
                  () => _sel.contains(s) ? _sel.remove(s) : _sel.add(s)),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, <LeadStatus>{}),
                    child: const Text('Any status'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _sel),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable, multi-select filter sheet reused for country and source.
/// Returns the chosen set (empty set = "all"), or null if dismissed.
class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final String allLabel;
  final List<String> options;
  final Set<String> selected;
  const _MultiSelectSheet({
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.options,
    required this.selected,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _sel = {...widget.selected};
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((c) => c.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.8;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_sel.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_sel.clear),
                      child: Text('Clear (${_sel.length})'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No matches',
                          style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final on = _sel.contains(c);
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(c),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (_) => setState(
                              () => on ? _sel.remove(c) : _sel.add(c)),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, <String>{}),
                      child: Text(widget.allLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _sel),
                      child: Text(
                          _sel.isEmpty ? 'Apply' : 'Apply (${_sel.length})'),
                    ),
                  ),
                ],
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
      itemBuilder: (_) => [for (final s in LeadSort.values) PopupMenuItem(value: s, child: Text(label(s)))],
      child: Chip(avatar: const Icon(Icons.sort, size: 16), label: Text(label(state.query.sort))),
    );
  }
}

class _LeadCard extends StatelessWidget {
  final Lead lead;
  final AppState state;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;
  const _LeadCard({required this.lead, required this.state, this.selecting = false, this.selected = false, required this.onToggleSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = <String>[if (lead.company.isNotEmpty) lead.company, if (lead.detectedCountry.isNotEmpty) lead.detectedCountry else if (lead.country.isNotEmpty && lead.country != 'global') lead.country, if (lead.publishedDate.isNotEmpty) lead.publishedDate];
    final isNew = state.isNew(lead);
    final seen = lead.seen;
    final titleColor = seen ? scheme.onSurfaceVariant : null;
    return Card(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : (isNew ? AppTheme.brandGreen.withValues(alpha: 0.07) : null),
      shape: (selected || isNew)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: selected ? scheme.primary : AppTheme.brandGreen,
                  width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: () => selecting ? onToggleSelect() : showLeadDetail(context, lead, state),
        onLongPress: onToggleSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selecting) ...[Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? scheme.primary : scheme.onSurfaceVariant), const SizedBox(width: 12)],
              Opacity(opacity: seen ? 0.7 : 1, child: ScoreBadge(lead.score)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.title.isEmpty ? '(no title)' : lead.title,
                      style: TextStyle(
                          fontWeight: seen ? FontWeight.w600 : FontWeight.w700,
                          height: 1.25,
                          color: titleColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta.join('  •  '),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isNew) const _FlagChip.brandNew(),
                        if (seen) const _FlagChip.seen(),
                        _tag(context, lead.sourceType.label, Icons.rss_feed, scheme.surfaceContainerHighest),
                        if (lead.projectType.isNotEmpty) _tag(context, lead.projectType, Icons.category_outlined, scheme.primary.withValues(alpha: 0.12)),
                        _StatusPill(status: lead.status),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (lead.imageUrl.isNotEmpty && !selecting) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LeadImage(
                      url: lead.imageUrl,
                      width: 52,
                      height: 52,
                      iconSize: 20),
                ),
              ],
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => state.toggleFavorite(lead),
                icon: Icon(lead.favorite ? Icons.star : Icons.star_border, color: lead.favorite ? Colors.amber : null),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _LeadGridCard extends StatelessWidget {
  final Lead lead;
  final AppState state;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;
  const _LeadGridCard({
    required this.lead,
    required this.state,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final place = lead.detectedCountry.isNotEmpty
        ? lead.detectedCountry
        : (lead.country.isNotEmpty && lead.country != 'global'
            ? lead.country
            : '');
    final meta = [
      if (lead.company.isNotEmpty) lead.company,
      if (place.isNotEmpty) place,
      if (lead.publishedDate.isNotEmpty) lead.publishedDate,
    ].join('  •  ');

    final isNew = state.isNew(lead);
    final seen = lead.seen;
    return Card(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : (isNew ? AppTheme.brandGreen.withValues(alpha: 0.07) : null),
      shape: (selected || isNew)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: selected ? scheme.primary : AppTheme.brandGreen,
                  width: 1.5))
          : null,
      child: InkWell(
        onTap: () => selecting
            ? onToggleSelect()
            : showLeadDetail(context, lead, state),
        onLongPress: onToggleSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                      opacity: seen ? 0.7 : 1,
                      child: ScoreBadge(lead.score, size: 38)),
                  const Spacer(),
                  if (isNew) const _FlagChip.brandNew(),
                  if (seen) const _FlagChip.seen(),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    onPressed: selecting
                        ? onToggleSelect
                        : () => state.toggleFavorite(lead),
                    icon: Icon(
                      selecting
                          ? (selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked)
                          : (lead.favorite
                              ? Icons.star
                              : Icons.star_border),
                      color: selecting
                          ? scheme.primary
                          : (lead.favorite ? Colors.amber : null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lead.title.isEmpty ? '(no title)' : lead.title,
                style: TextStyle(
                    fontWeight: seen ? FontWeight.w600 : FontWeight.w700,
                    height: 1.25,
                    color: seen ? scheme.onSurfaceVariant : null),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(status: lead.status),
                  if (lead.projectType.isNotEmpty)
                    _MetaTag(
                      text: lead.projectType,
                      icon: Icons.category_outlined,
                      bg: scheme.primary.withValues(alpha: 0.12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A "New" / "Seen" flag chip. "New" is a solid brand-green badge; "Seen" is
/// a muted outline so read items recede.
class _FlagChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool solid;
  const _FlagChip(
      {required this.text, required this.icon, required this.solid});

  const _FlagChip.brandNew()
      : text = 'New',
        icon = Icons.fiber_new,
        solid = true;
  const _FlagChip.seen()
      : text = 'Seen',
        icon = Icons.check_circle_outline,
        solid = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = solid ? AppTheme.brandGreen : scheme.onSurfaceVariant;
    final fg = solid ? Colors.white : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A small tinted tag with an icon — the same style used for the source and
/// project-type chips in the list card.
class _MetaTag extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color bg;
  const _MetaTag({required this.text, required this.icon, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
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
            Icon(Icons.travel_explore, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No leads yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh, or tap Refresh to scan your sources for the\n'
              'first time. New mill / grain / tender leads will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: state.refreshing ? null : () => state.refresh(), icon: const Icon(Icons.refresh), label: const Text('Scan sources now')),
          ],
        ),
      ),
    );
  }
}
