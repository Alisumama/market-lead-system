import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'headless_refresh.dart';
import 'settings_service.dart';

const _wmTask = 'bastak-refresh';
const _launchdLabel = 'com.bastak.bastakLeads.refresh';
const _winTask = 'BastakLeadsRefresh';

/// WorkManager entry point (Android). Runs in a background isolate, so it must
/// initialise the binding before touching plugins.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await runHeadlessRefresh();
    return true;
  });
}

/// Schedules unattended hourly refreshes that run even when the app is closed:
/// WorkManager on Android, a launchd LaunchAgent on macOS, a Scheduled Task on
/// Windows. Each invokes the app's headless refresh.
class BackgroundService {
  final SettingsService settings;
  BackgroundService(this.settings);

  bool get supported =>
      Platform.isAndroid || Platform.isMacOS || Platform.isWindows;

  /// Enables/disables the OS schedule. Returns the resulting state.
  Future<bool> setEnabled(bool on) async {
    try {
      if (on) {
        await _install();
      } else {
        await _remove();
      }
      await settings.setBackgroundEnabled(on);
      return on;
    } catch (_) {
      return settings.backgroundEnabled();
    }
  }

  Future<void> _install() async {
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        _wmTask,
        _wmTask,
        frequency: const Duration(hours: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } else if (Platform.isMacOS) {
      await _installLaunchd();
    } else if (Platform.isWindows) {
      await _installSchtasks();
    }
  }

  Future<void> _remove() async {
    if (Platform.isAndroid) {
      await Workmanager().cancelByUniqueName(_wmTask);
    } else if (Platform.isMacOS) {
      await _removeLaunchd();
    } else if (Platform.isWindows) {
      await _removeSchtasks();
    }
  }

  // ---- macOS launchd ----
  String get _plistPath =>
      '${Platform.environment['HOME']}/Library/LaunchAgents/$_launchdLabel.plist';

  Future<void> _installLaunchd() async {
    final exe = Platform.resolvedExecutable;
    final plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_launchdLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$exe</string>
    <string>--headless</string>
  </array>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>ProcessType</key>
  <string>Background</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
''';
    final f = File(_plistPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(plist);
    await Process.run('launchctl', ['unload', _plistPath]); // ignore if absent
    await Process.run('launchctl', ['load', '-w', _plistPath]);
  }

  Future<void> _removeLaunchd() async {
    await Process.run('launchctl', ['unload', '-w', _plistPath]);
    final f = File(_plistPath);
    if (await f.exists()) await f.delete();
  }

  // ---- Windows Task Scheduler ----
  Future<void> _installSchtasks() async {
    final exe = Platform.resolvedExecutable;
    await Process.run('schtasks', [
      '/Create', '/F', '/SC', 'HOURLY', '/TN', _winTask,
      '/TR', '"$exe" --headless',
    ]);
  }

  Future<void> _removeSchtasks() async {
    await Process.run('schtasks', ['/Delete', '/F', '/TN', _winTask]);
  }
}
