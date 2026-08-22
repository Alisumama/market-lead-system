import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../scoring/keyword_scorer.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/score_badge.dart';

/// Lets the user edit the keyword vocabulary that drives scoring, and try it
/// live against a sample headline. This is what makes the offline scorer feel
/// like something the user controls rather than a black box.
class ScoringEditorPage extends StatefulWidget {
  const ScoringEditorPage({super.key});

  @override
  State<ScoringEditorPage> createState() => _ScoringEditorPageState();
}

class _ScoringEditorPageState extends State<ScoringEditorPage> {
  ScoringConfig? _config;
  final _testCtrl = TextEditingController(
      text: 'New flour mill project: Acme Mills to build 500 tons/day plant in Nigeria');
  ScoreResult? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await context.read<AppState>().scoringConfig();
    setState(() {
      _config = c;
      _recompute();
    });
  }

  void _recompute() {
    if (_config == null) return;
    _preview = KeywordScorer(_config!).score(title: _testCtrl.text);
  }

  void _update(ScoringConfig c) => setState(() {
        _config = c;
        _recompute();
      });

  Future<void> _save() async {
    if (_config == null) return;
    await context.read<AppState>().saveScoringConfig(_config!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Scoring saved. Use "Re-score all" to apply.')));
    Navigator.pop(context);
  }

  Future<void> _reset() async {
    await context.read<AppState>().settings.resetScoringConfig();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoring keywords'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('Reset')),
          const SizedBox(width: 8),
          FilledButton(onPressed: c == null ? null : _save,
              child: const Text('Save')),
          const SizedBox(width: 12),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TryItCard(
                  controller: _testCtrl,
                  preview: _preview,
                  onChanged: (_) => setState(_recompute),
                ),
                const SizedBox(height: 16),
                _KeywordSection(
                  title: 'Facility terms',
                  help:
                      'Make an item in-scope: mills, silos, grain terminals, processing plants.',
                  icon: Icons.factory_outlined,
                  color: AppTheme.brandGreen,
                  terms: c.facilityTerms,
                  onChanged: (t) => _update(ScoringConfig(
                    facilityTerms: t,
                    intentTerms: c.intentTerms,
                    negativeTerms: c.negativeTerms,
                    relevanceCutoff: c.relevanceCutoff,
                  )),
                ),
                _KeywordSection(
                  title: 'Intent terms',
                  help:
                      'Signals of a real project: tender, construction, expansion, investment.',
                  icon: Icons.bolt_outlined,
                  color: const Color(0xFFE8A317),
                  terms: c.intentTerms,
                  onChanged: (t) => _update(ScoringConfig(
                    facilityTerms: c.facilityTerms,
                    intentTerms: t,
                    negativeTerms: c.negativeTerms,
                    relevanceCutoff: c.relevanceCutoff,
                  )),
                ),
                _KeywordSection(
                  title: 'Negative terms',
                  help:
                      'Pull the score down: price, forecast, earnings, weather, recall.',
                  icon: Icons.block,
                  color: Colors.red,
                  terms: c.negativeTerms,
                  onChanged: (t) => _update(ScoringConfig(
                    facilityTerms: c.facilityTerms,
                    intentTerms: c.intentTerms,
                    negativeTerms: t,
                    relevanceCutoff: c.relevanceCutoff,
                  )),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Relevance cutoff: ${c.relevanceCutoff}',
                            style:
                                Theme.of(context).textTheme.titleSmall),
                        const Text(
                            'Leads scoring below this are treated as not relevant.',
                            style: TextStyle(fontSize: 12)),
                        Slider(
                          value: c.relevanceCutoff.toDouble(),
                          min: 1,
                          max: 9,
                          divisions: 8,
                          label: '${c.relevanceCutoff}',
                          onChanged: (v) => _update(ScoringConfig(
                            facilityTerms: c.facilityTerms,
                            intentTerms: c.intentTerms,
                            negativeTerms: c.negativeTerms,
                            relevanceCutoff: v.round(),
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
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
  final ValueChanged<String> onChanged;
  const _TryItCard(
      {required this.controller,
      required this.preview,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
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
              Row(
                children: [
                  ScoreBadge(preview!.score),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          BandPill(preview!.score),
                          if (preview!.company.isNotEmpty)
                            _mini(preview!.company),
                          if (preview!.country.isNotEmpty)
                            _mini(preview!.country),
                          if (preview!.projectType.isNotEmpty)
                            _mini(preview!.projectType),
                        ]),
                        const SizedBox(height: 6),
                        Text(preview!.reasonText,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mini(String t) => Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: const TextStyle(fontSize: 10)),
        );
      });
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

  void _remove(String t) =>
      widget.onChanged(widget.terms.where((x) => x != t).toList());

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(width: 8),
              Text(widget.title,
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text('${widget.terms.length}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(widget.help,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in widget.terms)
                  InputChip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => _remove(t),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Add a term…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                    onPressed: _add, icon: const Icon(Icons.add)),
              ],
            ),
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
