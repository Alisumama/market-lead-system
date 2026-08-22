import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// A small floating pill that shows background-refresh status in a corner:
/// a spinner while fetching, then a brief success/failure confirmation that
/// fades away on its own. Idle = invisible and non-interactive.
class RefreshStatusChip extends StatefulWidget {
  const RefreshStatusChip({super.key});

  @override
  State<RefreshStatusChip> createState() => _RefreshStatusChipState();
}

class _RefreshStatusChipState extends State<RefreshStatusChip> {
  bool _wasRefreshing = false;
  bool _showResult = false;
  bool _resultError = false;
  String _resultText = '';
  Timer? _hideTimer;

  void _onFinished(AppState state) {
    _resultError = state.lastError != null;
    if (_resultError) {
      _resultText = 'Update failed';
    } else {
      final n = state.lastOutcome?.newLeads ?? 0;
      _resultText = n > 0 ? '$n new lead${n == 1 ? '' : 's'}' : 'Up to date';
    }
    _showResult = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showResult = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Detect the refreshing -> idle transition to flash a result.
    if (_wasRefreshing && !state.refreshing) {
      _onFinished(state);
    }
    _wasRefreshing = state.refreshing;

    final Widget child;
    if (state.refreshing) {
      child = _Pill(
        key: const ValueKey('loading'),
        icon: null,
        spinner: true,
        color: Theme.of(context).colorScheme.primary,
        text: state.refreshStatus ?? 'Updating leads…',
      );
    } else if (_showResult) {
      child = _Pill(
        key: ValueKey('result-$_resultText'),
        icon: _resultError ? Icons.error_outline : Icons.check_circle,
        spinner: false,
        color: _resultError
            ? Theme.of(context).colorScheme.error
            : AppTheme.brandGreen,
        text: _resultText,
        onTap: _resultError ? () => state.refresh() : null,
      );
    } else {
      child = const SizedBox.shrink(key: ValueKey('idle'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, 0.3), end: Offset.zero)
              .animate(anim),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final bool spinner;
  final Color color;
  final String text;
  final VoidCallback? onTap;

  const _Pill({
    super.key,
    required this.icon,
    required this.spinner,
    required this.color,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: scheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.refresh, size: 15, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
