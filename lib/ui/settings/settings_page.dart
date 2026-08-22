import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../widgets/brand_logo.dart';
import '../widgets/version_text.dart';
import 'scoring_editor.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
              floating: true, titleSpacing: 20, title: Text('Settings')),
          SliverList(
            delegate: SliverChildListDelegate([
              _section(context, 'Appearance'),
              _card(context, [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Theme'),
                  subtitle: Text(switch (state.themeMode) {
                    ThemeMode.system => 'Follow system',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode)),
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (s) =>
                        state.setThemeMode(s.first),
                    showSelectedIcon: false,
                  ),
                ),
              ]),

              _section(context, 'Data & refresh'),
              _card(context, [
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('Auto-refresh hourly'),
                  subtitle: Text(state.autoRefreshHourly
                      ? 'Scans sources at the top of every hour (:00) while the '
                          'app is open${_nextRefreshSuffix(state)}'
                      : 'Off — reload manually with Refresh now'),
                  value: state.autoRefreshHourly,
                  onChanged: state.setAutoRefreshHourly,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Reload new data now'),
                  subtitle: Text(state.refreshing
                      ? (state.refreshStatus ?? 'Working…')
                      : 'Fetch and score the latest leads from all sources'),
                  trailing: state.refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: state.refreshing ? null : () => state.refresh(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Freshness window'),
                  subtitle: Text(
                      'Items published within ${state.freshDays} days count as Fresh'),
                  trailing: DropdownButton<int>(
                    value: state.freshDays,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 d')),
                      DropdownMenuItem(value: 60, child: Text('60 d')),
                      DropdownMenuItem(value: 90, child: Text('90 d')),
                      DropdownMenuItem(value: 180, child: Text('180 d')),
                      DropdownMenuItem(value: 365, child: Text('1 yr')),
                    ],
                    onChanged: (v) =>
                        v != null ? state.setFreshDays(v) : null,
                  ),
                ),
              ]),

              _section(context, 'Notifications'),
              _card(context, [_NotificationSettings(state: state)]),

              _section(context, 'Scoring'),
              _card(context, [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Keyword vocabulary'),
                  subtitle: const Text(
                      'Tune the facility / intent / negative terms used to score leads'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ScoringEditorPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Re-score all leads'),
                  subtitle: const Text(
                      'Apply the current keywords to every stored lead (skips ones you overrode)'),
                  trailing: state.refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: state.refreshing
                      ? null
                      : () async {
                          await state.rescoreAll();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(state.refreshStatus ??
                                'Re-scored')),
                          );
                        },
                ),
              ]),

              _section(context, 'Data management'),
              _card(context, [_DataManagementTile(state: state)]),

              _section(context, 'Security'),
              _card(context, [_SecurityTile(state: state)]),

              _section(context, 'About'),
              _card(context, [
                ListTile(
                  leading: const SizedBox(
                      width: 40,
                      child: BrandLogo.mark(height: 32)),
                  title: const Text('Bastak Leads'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                          'Local, offline lead radar for grain / flour / milling '
                          'projects. No account, no cloud — your data stays on '
                          'this device.'),
                      SizedBox(height: 6),
                      VersionText(textAlign: TextAlign.start),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }

  String _nextRefreshSuffix(AppState state) {
    final at = state.nextRefreshAt;
    if (at == null) return '';
    final hh = at.hour.toString().padLeft(2, '0');
    return '. Next run at $hh:00';
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Text(title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  Widget _card(BuildContext context, List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(child: Column(children: children)),
      );
}

class _SecurityTile extends StatelessWidget {
  final AppState state;
  const _SecurityTile({required this.state});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(state.settings);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.pin_outlined),
          title: const Text('Change PIN'),
          subtitle: const Text('Update your local unlock PIN'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _changePin(context, auth),
        ),
        const Divider(height: 1),
        FutureBuilder<bool>(
          future: state.settings.biometricEnabled(),
          builder: (context, snap) {
            final enabled = snap.data ?? true;
            return SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text('Use ${auth.biometricLabel()}'),
              subtitle: const Text('Unlock with device biometrics'),
              value: enabled,
              onChanged: (v) => state.setBiometricEnabled(v),
            );
          },
        ),
      ],
    );
  }

  Future<void> _changePin(BuildContext context, AuthService auth) async {
    final ctrl = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'New PIN'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      if (ctrl.text.trim().length >= 4 &&
          ctrl.text.trim() == confirm.text.trim()) {
        await auth.changePin(ctrl.text.trim());
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN updated')));
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('PINs must match and be at least 4 digits')));
      }
    }
    ctrl.dispose();
    confirm.dispose();
  }
}

class _NotificationSettings extends StatelessWidget {
  final AppState state;
  const _NotificationSettings({required this.state});

  @override
  Widget build(BuildContext context) {
    final on = state.notifEnabled;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Enable notifications'),
          subtitle: const Text('Local device notifications — nothing is sent '
              'anywhere online'),
          value: on,
          onChanged: (v) async {
            final result = await state.setNotifEnabled(v);
            if (v && !result && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Notification permission was denied. Enable it in your '
                      'OS settings, then try again.')));
            }
          },
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: const Text('Notify after auto-refresh'),
          subtitle: const Text(
              'Get a summary each time the hourly refresh finishes'),
          value: state.notifAfterRefresh,
          onChanged: on ? state.setNotifAfterRefresh : null,
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.fiber_new_outlined),
          title: const Text('Only when new leads are found'),
          subtitle: const Text('Skip the "no new leads" notification'),
          value: state.notifOnlyNew,
          onChanged: on ? state.setNotifOnlyNew : null,
        ),
        const Divider(height: 1),
        ListTile(
          enabled: on,
          leading: const Icon(Icons.filter_alt_outlined),
          title: const Text('Only notify for score ≥'),
          subtitle: Text(state.notifMinScore == 0
              ? 'Any new lead'
              : 'Leads scoring ${state.notifMinScore} or higher'),
          trailing: DropdownButton<int>(
            value: state.notifMinScore,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Any')),
              DropdownMenuItem(value: 4, child: Text('≥ 4')),
              DropdownMenuItem(value: 6, child: Text('≥ 6')),
              DropdownMenuItem(value: 8, child: Text('≥ 8 (hot)')),
            ],
            onChanged: on
                ? (v) => v != null ? state.setNotifMinScore(v) : null
                : null,
          ),
        ),
        const Divider(height: 1),
        ListTile(
          enabled: on,
          leading: const Icon(Icons.send_outlined),
          title: const Text('Send test notification'),
          trailing: const Icon(Icons.chevron_right),
          onTap: on
              ? () async {
                  await state.sendTestNotification();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Test notification sent')));
                }
              : null,
        ),
      ],
    );
  }
}

class _DataManagementTile extends StatelessWidget {
  final AppState state;
  const _DataManagementTile({required this.state});

  Future<void> _exportAll(BuildContext context) async {
    final leads = await state.allLeadsForExport();
    if (leads.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No leads to export yet')));
      return;
    }
    try {
      final path = await ExportService().exportCsv(leads);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported ${leads.length} leads → $path')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all leads?'),
        content: const Text(
            'This permanently deletes every stored lead from this device. '
            'Your sources and settings are kept. Leads may reappear on the '
            'next refresh if the sources still list them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final n = await state.clearAllLeads();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted $n leads')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export all leads (CSV)'),
          subtitle: Text('${state.stats.total} leads on this device'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _exportAll(context),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text('Clear all leads',
              style: TextStyle(color: scheme.error)),
          subtitle: const Text('Delete every stored lead (keeps sources)'),
          onTap: () => _clearAll(context),
        ),
      ],
    );
  }
}
