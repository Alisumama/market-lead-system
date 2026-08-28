import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/update_service.dart';
import '../../state/app_state.dart';
import '../reports/reports_page.dart';
import '../rules/rules_page.dart';
import '../settings/settings_page.dart';
import '../sources/sources_page.dart';
import '../updates/update_dialog.dart';
import '../users/users_page.dart';
import '../widgets/brand_logo.dart';
import '../widgets/refresh_status_chip.dart';
import 'leads_page.dart';

/// Adaptive scaffold: a NavigationRail on wide screens (desktop) and a
/// NavigationBar on narrow ones (mobile), so one codebase feels native on
/// Windows, macOS and Android.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _updatePrompted = false;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, sel: Icons.dashboard, label: 'Leads'),
    (icon: Icons.rss_feed_outlined, sel: Icons.rss_feed, label: 'Sources'),
    (icon: Icons.tune_outlined, sel: Icons.tune, label: 'Rules'),
    (icon: Icons.bar_chart_outlined, sel: Icons.bar_chart, label: 'Reports'),
    (icon: Icons.group_outlined, sel: Icons.group, label: 'Users'),
    (icon: Icons.settings_outlined, sel: Icons.settings, label: 'Settings'),
  ];

  /// Overlays the background-refresh status pill in the bottom-left of the
  /// content area (clear of the Sources FAB and the bottom nav bar).
  Widget _withStatus(Widget child) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          left: 16,
          bottom: 16,
          child: SafeArea(child: RefreshStatusChip()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Report drill-downs request a tab jump (e.g. tap "Warm" → Leads).
    final pending = context.select<AppState, int?>((s) => s.pendingTab);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _index = pending);
        context.read<AppState>().consumeTabRequest();
      });
    }

    // Surface a found update once per session (Windows). Mandatory ones can't
    // be dismissed by the dialog itself.
    final update = context.select<AppState, UpdateInfo?>((s) => s.availableUpdate);
    if (update != null && !_updatePrompted) {
      _updatePrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdateDialog(context, update);
      });
    }

    final pages = const [
      LeadsPage(),
      SourcesPage(),
      RulesPage(),
      ReportsPage(),
      UsersPage(),
      SettingsPage()
    ];
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(
              index: _index,
              onSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _withStatus(pages[_index])),
          ],
        ),
      );
    }

    return Scaffold(
      body: _withStatus(pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.sel),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;
  final List<({IconData icon, IconData sel, String label})> destinations;

  const _Rail({
    required this.index,
    required this.onSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: const BrandLogo.horizontal(height: 30),
            ),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < destinations.length; i++)
            _RailTile(
              d: destinations[i],
              selected: i == index,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _RefreshCard(state: state),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  final ({IconData icon, IconData sel, String label}) d;
  final bool selected;
  final VoidCallback onTap;
  const _RailTile(
      {required this.d, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(selected ? d.sel : d.icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    size: 22),
                const SizedBox(width: 14),
                Text(d.label,
                    style: TextStyle(
                      color:
                          selected ? scheme.primary : scheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshCard extends StatelessWidget {
  final AppState state;
  const _RefreshCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('Auto-refresh',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              state.autoRefreshHourly
                  ? (state.nextRefreshAt != null
                      ? 'Next at ${state.nextRefreshAt!.hour.toString().padLeft(2, '0')}:00'
                      : 'Hourly at :00')
                  : 'Manual only',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed:
                    state.refreshing ? null : () => state.refresh(),
                icon: state.refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(state.refreshing ? 'Working…' : 'Refresh now'),
              ),
            ),
            if (state.refreshStatus != null) ...[
              const SizedBox(height: 8),
              Text(state.refreshStatus!,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
