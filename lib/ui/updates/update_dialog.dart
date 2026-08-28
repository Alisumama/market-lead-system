import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/update_service.dart';
import '../../state/app_state.dart';

/// Shows the "update available" prompt. Mandatory updates can't be dismissed.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null until the download starts
  bool _installing = false;
  String? _error;

  Future<void> _update() async {
    final updater = context.read<AppState>().updater;
    setState(() {
      _installing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await updater.download(
        widget.info,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      // Hands off to the installer and terminates this process.
      await updater.installAndExit(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final canDismiss = !info.mandatory && !_installing;
    return PopScope(
      canPop: canDismiss,
      child: AlertDialog(
        title: Text('Update available — v${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.notes.trim().isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(child: Text(info.notes.trim())),
              )
            else
              const Text('A new version is available.'),
            if (info.mandatory) ...[
              const SizedBox(height: 10),
              Text('This update is required to continue.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600)),
            ],
            if (_installing) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                  value: (_progress ?? 0) > 0 ? _progress : null),
              const SizedBox(height: 6),
              Text(
                _progress == null || _progress == 0
                    ? 'Starting download…'
                    : 'Downloading… ${((_progress ?? 0) * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          if (canDismiss)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: _installing ? null : _update,
            child: Text(_error != null ? 'Retry' : 'Update & restart'),
          ),
        ],
      ),
    );
  }
}
