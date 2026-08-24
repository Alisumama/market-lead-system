import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/lead.dart';
import '../../scoring/keyword_scorer.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_bar_bits.dart';
import '../widgets/multi_select_sheet.dart';
import '../widgets/score_badge.dart';

/// The Rules module — a first-class, shareable data-quality engine: scoring
/// weights, keyword vocabulary, and acceptance/rejection filters. Import/export
/// like a source registry. The goal: keep only the finest, convertible leads.
class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  ScoringConfig? _cfg;
  final _testCtrl = TextEditingController(
      text:
          'New flour mill: Acme Mills to build 500 tons/day plant in Nigeria');
  ScoreResult? _preview;
  RejectReason? _previewReject;
  Map<String, dynamic>? _rejectStats;
  List<RuleProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final c = await state.scoringConfig();
    final stats = await state.rejectStats();
    final profiles = await state.ruleProfiles();
    if (!mounted) return;
    setState(() {
      _cfg = c;
      _rejectStats = stats;
      _profiles = profiles;
      _recompute();
    });
  }

  void _recompute() {
    if (_cfg == null) return;
    final scorer = KeywordScorer(_cfg!);
    _preview = scorer.score(title: _testCtrl.text);
    _previewReject =
        scorer.reject(title: _testCtrl.text, score: _preview!.score);
  }

  void _update(ScoringConfig c) => setState(() {
        _cfg = c;
        _recompute();
      });

  Future<void> _save() async {
    if (_cfg == null) return;
    await context.read<AppState>().saveScoringConfig(_cfg!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rules saved. Use "Re-score all" to apply to '
            'existing leads; new fetches use them automatically.')));
  }

  Future<void> _export() async {
    if (_cfg == null) return;
    final path = await ExportService().exportScoringConfig(_cfg!);
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Rules exported → $path')));
  }

  Future<void> _import() async {
    try {
      final c = await ExportService().importScoringConfig();
      if (c == null || !mounted) return;
      _update(c);
      await _save();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _reset() async {
    await context.read<AppState>().settings.resetScoringConfig();
    await _load();
  }

  // ---------------- profiles ----------------

  Future<void> _saveProfileAs() async {
    if (_cfg == null) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final next = [
      for (final p in _profiles)
        if (p.name.toLowerCase() != trimmed.toLowerCase()) p,
      RuleProfile(trimmed, _cfg!),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await state.saveRuleProfiles(next);
    if (!mounted) return;
    setState(() => _profiles = next);
    messenger
        .showSnackBar(SnackBar(content: Text('Saved profile "$trimmed"')));
  }

  void _loadProfile(RuleProfile p) {
    _update(p.config);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Loaded "${p.name}". Tap Save to apply it.')));
  }

  Future<void> _deleteProfile(RuleProfile p) async {
    final next = [for (final e in _profiles) if (e.name != p.name) e];
    await context.read<AppState>().saveRuleProfiles(next);
    if (!mounted) return;
    setState(() => _profiles = next);
  }

  Future<String?> _promptName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save profile as'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Strict, Wide net'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _profilesCard(BuildContext context, ScoringConfig c) {
    final scheme = Theme.of(context).colorScheme;
    return _card(context, 'Profiles', Icons.bookmarks_outlined, [
      Text(
        'Save the current rules as a named set and switch between them.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in _profiles)
            InputChip(
              label: Text(p.name),
              avatar: const Icon(Icons.bookmark, size: 18),
              onPressed: () => _loadProfile(p),
              onDeleted: () => _deleteProfile(p),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Save current…'),
            onPressed: _saveProfileAs,
          ),
        ],
      ),
    ]);
  }

  // ---------------- rejection analytics + dry-run ----------------

  String _reasonLabel(String name) {
    final match = RejectReason.values.where((e) => e.name == name);
    return match.isEmpty ? name : match.first.label;
  }

  Widget _analyticsCard(BuildContext context, ScoringConfig c) {
    final scheme = Theme.of(context).colorScheme;
    final stats = _rejectStats;
    final byReason = (stats?['byReason'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = byReason.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    return _card(context, 'Data quality', Icons.insights_outlined, [
      if (stats == null)
        Text('Run a refresh to see how many items the rules dropped.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
      else ...[
        Text(
          'Last run: scanned ${stats['scanned']}, kept ${stats['newLeads']} '
          'new, rejected ${stats['rejected']}.',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in entries)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${_reasonLabel(e.key)}: ${e.value}',
                      style: const TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ],
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _dryRun(c),
          icon: const Icon(Icons.science_outlined, size: 18),
          label: const Text('Test these rules on current leads'),
        ),
      ),
    ]);
  }

  Future<void> _dryRun(ScoringConfig c) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Testing rules against stored leads…')));
    final r = await state.dryRunRules(c);
    if (!mounted) return;
    final entries = r.byReason.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dry run'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Against ${r.total} stored leads, these rules would:'),
            const SizedBox(height: 8),
            Text('• keep ${r.kept}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('• drop ${r.dropped}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Dropped by reason:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final e in entries)
                Text('  ${_reasonLabel(e.key.name)}: ${e.value}',
                    style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              'Preview only — stored leads are unchanged. Items the current '
              'rules already rejected are not stored, so they can\'t appear here.',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _cfg;
    return Scaffold(
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
            title: const Text('Rules'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'export') _export();
                  if (v == 'import') _import();
                  if (v == 'reset') _reset();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'import', child: Text('Import rules')),
                  PopupMenuItem(value: 'export', child: Text('Export rules')),
                  PopupMenuItem(value: 'reset', child: Text('Reset to default')),
                ],
              ),
              FilledButton(
                  onPressed: c == null ? null : _save,
                  child: const Text('Save')),
              const SizedBox(width: 12),
            ],
          ),
          if (c == null)
            const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_sections(context, c)),
              ),
            ),
        ],
      ),
      floatingActionButton: c == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final state = context.read<AppState>();
                final messenger = ScaffoldMessenger.of(context);
                await _save();
                await state.rescoreAll();
                messenger.showSnackBar(SnackBar(
                    content: Text(state.refreshStatus ?? 'Re-scored')));
              },
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Re-score all'),
            ),
    );
  }

  List<Widget> _sections(BuildContext context, ScoringConfig c) => [
        _profilesCard(context, c),
        _TryItCard(
            controller: _testCtrl,
            preview: _preview,
            reject: _previewReject,
            onChanged: (_) => setState(_recompute)),
        _analyticsCard(context, c),
        _card(context, 'Scoring weights', Icons.tune, [
          _slider('In-scope facility', c.facilityWeight, 0, 8,
              (v) => _update(c.copyWith(facilityWeight: v))),
          _slider('Project intent', c.intentWeight, 0, 5,
              (v) => _update(c.copyWith(intentWeight: v))),
          _slider('Stated capacity', c.capacityWeight, 0, 5,
              (v) => _update(c.copyWith(capacityWeight: v))),
          _slider('Stated budget', c.budgetWeight, 0, 5,
              (v) => _update(c.copyWith(budgetWeight: v))),
          _slider('Named company', c.companyWeight, 0, 5,
              (v) => _update(c.copyWith(companyWeight: v))),
          _slider('Negative penalty', c.negativeWeight, 0, 5,
              (v) => _update(c.copyWith(negativeWeight: v))),
          _slider('Tender-source boost', c.tenderBoost, 0, 5,
              (v) => _update(c.copyWith(tenderBoost: v))),
          _slider('Recency boost', c.recencyBoost, 0, 5,
              (v) => _update(c.copyWith(recencyBoost: v))),
          _slider('Recency window (days)', c.recencyDays, 7, 180,
              (v) => _update(c.copyWith(recencyDays: v)),
              step: 7),
          _slider('Relevance cutoff', c.relevanceCutoff, 1, 9,
              (v) => _update(c.copyWith(relevanceCutoff: v))),
        ]),
        _KeywordSection(
          title: 'Facility terms',
          help: 'In-scope facilities: mills, silos, terminals, plants.',
          icon: Icons.factory_outlined,
          color: AppTheme.brandGreen,
          terms: c.facilityTerms,
          onChanged: (t) => _update(c.copyWith(facilityTerms: t)),
        ),
        _KeywordSection(
          title: 'Intent terms',
          help: 'Project signals: tender, construction, expansion, investment.',
          icon: Icons.bolt_outlined,
          color: const Color(0xFFE8A317),
          terms: c.intentTerms,
          onChanged: (t) => _update(c.copyWith(intentTerms: t)),
        ),
        _KeywordSection(
          title: 'Negative terms',
          help: 'Pull the score down: price, forecast, earnings, weather.',
          icon: Icons.block,
          color: Colors.red,
          terms: c.negativeTerms,
          onChanged: (t) => _update(c.copyWith(negativeTerms: t)),
        ),
        _KeywordSection(
          title: 'Required keywords (topic gate)',
          help: 'If set, an item is rejected unless it contains at least one.',
          icon: Icons.rule,
          color: const Color(0xFF6C63FF),
          terms: c.requiredKeywords,
          onChanged: (t) => _update(c.copyWith(requiredKeywords: t)),
        ),
        _KeywordSection(
          title: 'Blocked keywords',
          help: 'Reject any item containing one of these.',
          icon: Icons.do_not_disturb_on_outlined,
          color: Colors.redAccent,
          terms: c.blockedKeywords,
          onChanged: (t) => _update(c.copyWith(blockedKeywords: t)),
        ),
        _card(context, 'Acceptance filters (reject data)', Icons.filter_alt, [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Require an in-scope facility'),
            subtitle: const Text('Reject items with no mill/silo/plant term'),
            value: c.requireFacility,
            onChanged: (v) => _update(c.copyWith(requireFacility: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reject items with no date'),
            value: c.rejectUndated,
            onChanged: (v) => _update(c.copyWith(rejectUndated: v)),
          ),
          _slider('Minimum score to keep', c.minScoreToStore, 0, 10,
              (v) => _update(c.copyWith(minScoreToStore: v)),
              hint: c.minScoreToStore == 0 ? 'off' : null),
          _dropdownDays(
            context,
            'Max age (reject older)',
            c.maxAgeDays,
            (v) => _update(c.copyWith(maxAgeDays: v)),
          ),
          _dropdownInt(
            context,
            'Min capacity (tons/day)',
            c.minCapacityTpd == 0
                ? 'off — any capacity'
                : 'reject if stated capacity < ${c.minCapacityTpd} t/d',
            c.minCapacityTpd,
            const {
              0: 'Off',
              50: '50',
              100: '100',
              200: '200',
              500: '500',
              1000: '1000',
            },
            (v) => _update(c.copyWith(minCapacityTpd: v)),
          ),
          _dropdownInt(
            context,
            'Min budget (USD)',
            c.minBudgetUsd == 0
                ? 'off — any budget'
                : 'reject if stated budget < ${_money(c.minBudgetUsd)}',
            c.minBudgetUsd,
            const {
              0: 'Off',
              100000: r'$100k',
              500000: r'$500k',
              1000000: r'$1M',
              5000000: r'$5M',
              10000000: r'$10M',
            },
            (v) => _update(c.copyWith(minBudgetUsd: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'Capacity/budget gates only drop items that state a figure below '
              'the bar — items with no figure are kept.',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          _multiTile(context, 'Only these countries', c.allowedCountries,
              _countryOptions(context),
              (s) => _update(c.copyWith(allowedCountries: s))),
          _multiTile(context, 'Block these countries', c.blockedCountries,
              _countryOptions(context),
              (s) => _update(c.copyWith(blockedCountries: s))),
          _multiTile(context, 'Only these languages', c.allowedLanguages,
              const ['en', 'tr', 'ru', 'ar', 'fr', 'ur', 'es', 'pt'],
              (s) => _update(c.copyWith(allowedLanguages: s))),
          _multiTile(
              context,
              'Only these source types',
              c.allowedSourceKinds,
              SourceKind.values.map((k) => k.storageValue).toList(),
              (s) => _update(c.copyWith(allowedSourceKinds: s))),
        ]),
        const SizedBox(height: 12),
      ];

  List<String> _countryOptions(BuildContext context) {
    final fromData = context.read<AppState>().countries;
    final base = [
      'Pakistan', 'Turkey', 'Nigeria', 'Kenya', 'Egypt', 'Ethiopia',
      'Tanzania', 'Uganda', 'Mozambique', 'Kazakhstan', 'Russia', 'Ukraine',
      'Saudi Arabia', 'UAE', 'India', 'Bangladesh', 'Morocco', 'Algeria',
      'Ghana', 'Iraq',
    ];
    return {...base, ...fromData}.toList()..sort();
  }

  Widget _card(BuildContext context, String title, IconData icon,
      List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max,
      ValueChanged<int> onChanged,
      {int step = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 150,
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: ((max - min) / step).round(),
              label: '$value',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(hint ?? '$value',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _dropdownDays(BuildContext context, String label, int value,
      ValueChanged<int> onChanged) {
    return _dropdownInt(
      context,
      label,
      value == 0 ? 'off — keep any age' : 'within $value days',
      value,
      const {0: 'Off', 30: '30 d', 90: '3 mo', 180: '6 mo', 365: '1 yr'},
      onChanged,
    );
  }

  /// A labelled preset dropdown for an int setting. Any current value that
  /// isn't one of [presets] (e.g. an imported/custom number) gets its own
  /// injected item so the DropdownButton always has exactly one match.
  Widget _dropdownInt(BuildContext context, String label, String subtitle,
      int value, Map<int, String> presets, ValueChanged<int> onChanged) {
    final items = {
      ...presets,
      if (!presets.containsKey(value)) value: '$value',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => v != null ? onChanged(v) : null,
      ),
    );
  }

  static String _money(int usd) {
    if (usd >= 1000000) {
      final m = usd / 1000000;
      return '\$${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
    }
    if (usd >= 1000) return '\$${(usd / 1000).round()}k';
    return '\$$usd';
  }

  Widget _multiTile(BuildContext context, String label, Set<String> selected,
      List<String> options, ValueChanged<Set<String>> onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(selected.isEmpty ? 'Any' : selected.join(', ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showModalBottomSheet<Set<String>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => MultiSelectSheet(
            title: label,
            searchHint: 'Search…',
            allLabel: 'Any',
            options: options,
            selected: selected,
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  @override
  void dispose() {
    _testCtrl.dispose();
    super.dispose();
  }
}

class _TryItCard extends StatelessWidget {
  final TextEditingController controller;
  final ScoreResult? preview;
  final RejectReason? reject;
  final ValueChanged<String> onChanged;
  const _TryItCard(
      {required this.controller,
      required this.preview,
      required this.reject,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Try it', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              onChanged: onChanged,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'Type a sample headline to preview its score…'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                ScoreBadge(preview!.score),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BandPill(preview!.score),
                      const SizedBox(height: 6),
                      Text(preview!.reasonText,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _AcceptChip(reject: reject),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows whether the sample would pass the acceptance filters, and why not.
class _AcceptChip extends StatelessWidget {
  final RejectReason? reject;
  const _AcceptChip({required this.reject});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accepted = reject == null;
    final color = accepted ? AppTheme.brandGreen : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(accepted ? Icons.check_circle : Icons.block,
              size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              accepted
                  ? 'Accepted — passes the acceptance filters'
                  : 'Rejected — ${reject!.label}',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeywordSection extends StatefulWidget {
  final String title;
  final String help;
  final IconData icon;
  final Color color;
  final List<String> terms;
  final ValueChanged<List<String>> onChanged;
  const _KeywordSection({
    required this.title,
    required this.help,
    required this.icon,
    required this.color,
    required this.terms,
    required this.onChanged,
  });

  @override
  State<_KeywordSection> createState() => _KeywordSectionState();
}

class _KeywordSectionState extends State<_KeywordSection> {
  final _addCtrl = TextEditingController();

  void _add() {
    final t = _addCtrl.text.trim().toLowerCase();
    if (t.isEmpty || widget.terms.contains(t)) return;
    widget.onChanged([...widget.terms, t]);
    _addCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.title,
                      style: Theme.of(context).textTheme.titleSmall)),
              Text('${widget.terms.length}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(widget.help,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (widget.terms.isEmpty)
              Text('None set',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in widget.terms)
                    InputChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => widget
                          .onChanged(widget.terms.where((x) => x != t).toList()),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'Add a term…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  onPressed: _add, icon: const Icon(Icons.add)),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }
}
