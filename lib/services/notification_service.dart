import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

/// Cross-platform local notifications with graceful degradation:
///   • Android / macOS / iOS / Linux -> flutter_local_notifications
///   • Windows                       -> local_notifier
/// Every call is guarded so a platform that isn't set up simply does nothing
/// rather than crashing the app.
class NotificationService {
  bool _inited = false;
  int _id = 0;
  FlutterLocalNotificationsPlugin? _fln;

  bool get _useLocalNotifier => Platform.isWindows;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      if (_useLocalNotifier) {
        await localNotifier.setup(appName: 'Bastak Leads');
        return;
      }
      final fln = FlutterLocalNotificationsPlugin();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linux =
          LinuxInitializationSettings(defaultActionName: 'Open');
      await fln.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
          linux: linux,
        ),
      );
      _fln = fln;
    } catch (_) {
      // Leave the service in a no-op state.
    }
  }

  /// Ask the OS for permission (called when the user enables notifications).
  /// Returns true if granted (or if the platform needs no explicit grant).
  Future<bool> requestPermission() async {
    await init();
    try {
      if (_useLocalNotifier) return true;
      if (Platform.isAndroid) {
        final impl = _fln?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return (await impl?.requestNotificationsPermission()) ?? true;
      }
      if (Platform.isMacOS) {
        final impl = _fln?.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        return (await impl?.requestPermissions(
                alert: true, badge: true, sound: true)) ??
            true;
      }
      if (Platform.isIOS) {
        final impl = _fln?.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return (await impl?.requestPermissions(
                alert: true, badge: true, sound: true)) ??
            true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> show(String title, String body) async {
    await init();
    try {
      if (_useLocalNotifier) {
        final n = LocalNotification(title: title, body: body);
        await n.show();
        return;
      }
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'refresh_updates',
          'Refresh updates',
          channelDescription: 'Summaries after leads are refreshed',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      );
      _id = (_id + 1) & 0x7fffffff;
      await _fln?.show(
        id: _id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {
      // Never let a notification failure affect the pipeline.
    }
  }
}
