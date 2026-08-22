import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/lead.dart';
import '../../services/share_helper.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../util/text.dart';
import '../widgets/lead_image.dart';
import '../widgets/score_badge.dart';

/// Opens the lead detail. On wide screens it slides in as a panel docked to the
/// right edge at 50% width; on phones it pushes a full page.
Future<void> showLeadDetail(
    BuildContext context, Lead lead, AppState state) {
  // Opening a lead marks it seen (dulls it in the list, drops the "new" flag).
  state.markSeen(lead);
  final wide = MediaQuery.sizeOf(context).width >= 800;

  if (!wide) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Lead')),
        body: SafeArea(child: LeadDetailView(lead: lead, state: state)),
      ),
    ));
  }

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, anim, secondaryAnim) => Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 1,
        child: Material(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          elevation: 16,
          child: SafeArea(
            child: LeadDetailView(
              lead: lead,
              state: state,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Full lead view with complete user control: override the score, change the
/// pipeline status, star it, write notes, open the source, or delete it.
/// Fills its parent's height; used both in the right-side panel and the
/// full-page (mobile) route.
class LeadDetailView extends StatefulWidget {
  final Lead lead;
  final AppState state;

  /// Non-null when shown as a dialog panel — renders a close (✕) button.
  final VoidCallback? onClose;

  const LeadDetailView(
      {super.key, required this.lead, required this.state, this.onClose});

  @override
  State<LeadDetailView> createState() => _LeadDetailViewState();
}

class _LeadDetailViewState extends State<LeadDetailView> {
  late Lead _lead = widget.lead;
  late final TextEditingController _notesCtrl =
      TextEditingController(text: _lead.notes);

  AppState get state => widget.state;

  void _dismiss() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(_lead.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _editScore() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _ScoreEditDialog(initial: _lead.score),
    );
    if (picked != null) {
      await state.overrideScore(_lead, picked);
      setState(() => _lead =
          _lead.copyWith(score: picked, scoreLocked: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cleanSummary = cleanHtmlText(_lead.summary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onClose != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _dismiss,
                ),
                const SizedBox(width: 4),
                Text('Lead detail',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              if (_lead.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: LeadImage(
                    url: _lead.imageUrl,
                    height: 170,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      ScoreBadge(_lead.score, size: 56),
                      const SizedBox(height: 6),
                      BandPill(_lead.score),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lead.title.isEmpty ? '(no title)' : _lead.title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.25),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          if (_lead.company.isNotEmpty)
                            _chip(Icons.business, _lead.company),
                          if (_lead.detectedCountry.isNotEmpty)
                            _chip(Icons.public, _lead.detectedCountry),
                          if (_lead.projectType.isNotEmpty)
                            _chip(
                                Icons.category_outlined, _lead.projectType),
                          if (_lead.publishedDate.isNotEmpty)
                            _chip(Icons.event, _lead.publishedDate),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await state.toggleFavorite(_lead);
                      setState(() =>
                          _lead = _lead.copyWith(favorite: !_lead.favorite));
                    },
                    icon: Icon(
                        _lead.favorite ? Icons.star : Icons.star_border,
                        color: _lead.favorite ? Colors.amber : null),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Why this score
              if (_lead.scoreReason.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.psychology_outlined,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text('Why this score',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        if (_lead.scoreLocked)
                          Text('overridden',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      Text(_lead.scoreReason,
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Summary
              if (cleanSummary.isNotEmpty) ...[
                Text('Summary',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(cleanSummary, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 16),
              ],

              // Status selector
              Text('Status', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in LeadStatus.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _lead.status == s,
                      onSelected: (_) async {
                        await state.setStatus(_lead, s);
                        setState(() => _lead = _lead.copyWith(status: s));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Notes
              Text('Your notes',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Add context, contacts, next steps…',
                ),
                onChanged: (v) => state.setNotes(_lead, v),
              ),
              const SizedBox(height: 20),

              // Actions
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _openUrl,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open source'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => shareLeads([_lead]),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _editScore,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Override score'),
                  ),
                  if (_lead.scoreLocked)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await state.unlockScore(_lead);
                        if (!mounted) return;
                        _dismiss();
                      },
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('Auto-score'),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error),
                    onPressed: () async {
                      final ok = await _confirmDelete(context);
                      if (ok == true) {
                        await state.deleteLead(_lead);
                        if (!mounted) return;
                        _dismiss();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String text) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 15),
      label: Text(text),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete lead?'),
        content: const Text(
            'This removes it from your local database. It may reappear on a '
            'future refresh if the source still lists it.'),
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

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }
}

class _ScoreEditDialog extends StatefulWidget {
  final int initial;
  const _ScoreEditDialog({required this.initial});
  @override
  State<_ScoreEditDialog> createState() => _ScoreEditDialogState();
}

class _ScoreEditDialogState extends State<_ScoreEditDialog> {
  late double _v = widget.initial.toDouble();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Override score'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_v.round()}',
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.scoreColor(_v.round()))),
          Slider(
            value: _v,
            min: 0,
            max: 10,
            divisions: 10,
            label: '${_v.round()}',
            onChanged: (x) => setState(() => _v = x),
          ),
          const Text(
            'Your score is locked and survives re-scoring until you switch '
            'it back to auto.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _v.round()),
            child: const Text('Save')),
      ],
    );
  }
}
