import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:workmanager/workmanager.dart';

import 'data/lead_repository.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/headless_refresh.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/auth/lock_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/splash_screen.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  // Headless mode: the OS scheduler launches us with --headless to collect in
  // the background, then we exit. No window, no auth.
  if (args.contains('--headless')) {
    runApp(const _HeadlessRunner());
    return;
  }

  // WorkManager background isolate (Android/iOS only).
  if (Platform.isAndroid || Platform.isIOS) {
    Workmanager().initialize(backgroundCallbackDispatcher);
  }

  final settings = SettingsService();
  final repo = LeadRepository();
  final auth = AuthService(settings);
  final notifications = NotificationService();

  runApp(BastakLeadsApp(
    settings: settings,
    repo: repo,
    auth: auth,
    notifications: notifications,
  ));
}

class BastakLeadsApp extends StatelessWidget {
  final SettingsService settings;
  final LeadRepository repo;
  final AuthService auth;
  final NotificationService notifications;

  const BastakLeadsApp({
    super.key,
    required this.settings,
    required this.repo,
    required this.auth,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          AppState(repo: repo, settings: settings, notifications: notifications),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Bastak Leads',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            home: AuthGate(auth: auth),
          );
        },
      ),
    );
  }
}

/// Runs a single background refresh then exits. runApp keeps the engine's run
/// loop pumping so plugin channels (DB, http, notifications) work.
class _HeadlessRunner extends StatefulWidget {
  const _HeadlessRunner();
  @override
  State<_HeadlessRunner> createState() => _HeadlessRunnerState();
}

class _HeadlessRunnerState extends State<_HeadlessRunner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await runHeadlessRefresh();
      exit(0);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Decides between the lock screen and the app, and initialises AppState once
/// the user is authenticated.
class AuthGate extends StatefulWidget {
  final AuthService auth;
  const AuthGate({super.key, required this.auth});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _splashDone = false;
  bool _unlocked = false;
  bool _initStarted = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start the data layer at launch — independent of unlock — so the radar
    // keeps collecting (and firing notifications) even while the app is locked.
    // Auth only gates viewing the leads, not background collection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initStarted) {
        _initStarted = true;
        context.read<AppState>().init();
      }
    });
  }

  void _onUnlocked() {
    setState(() => _unlocked = true);
    _resetIdleTimer();
  }

  void _lock() {
    if (!_unlocked) return;
    _idleTimer?.cancel();
    setState(() => _unlocked = false);
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (!_unlocked || !_initStarted) return;
    final mins = context.read<AppState>().autoLockMinutes;
    if (mins <= 0) return;
    _idleTimer = Timer(Duration(minutes: mins), _lock);
  }

  // Lock-on-background only applies to mobile. Desktop windows report
  // hidden/inactive whenever they merely lose focus (clicking a dialog or
  // another window), which would lock the app during normal use.
  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_unlocked || !_initStarted) return;
    if (state == AppLifecycleState.resumed) {
      _resetIdleTimer();
      return;
    }
    if (!_mobile) return; // desktop: ignore focus/occlusion changes
    final lockOnBg = context.read<AppState>().lockOnBackground;
    if (lockOnBg &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(onDone: () => setState(() => _splashDone = true));
    }
    if (!_unlocked) {
      return LockScreen(auth: widget.auth, onUnlocked: _onUnlocked);
    }
    // Any interaction resets the inactivity countdown.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerSignal: (_) => _resetIdleTimer(),
      onPointerMove: (_) => _resetIdleTimer(),
      child: const HomeShell(),
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
