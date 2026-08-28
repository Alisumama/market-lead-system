import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'data/lead_repository.dart';
import 'data/models/app_user.dart';
import 'data/user_repository.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/headless_refresh.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/auth/lock_screen.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/splash_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseReady = await _initFirebase();

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
    firebaseReady: firebaseReady,
  ));
}

/// Initialises Firebase without letting a failure take down the app. This is a
/// local-first radar: it must keep working fully offline, and on platforms
/// where the firebase_core plugin isn't available (e.g. Linux desktop) or
/// when there's no network, initialization simply no-ops instead of throwing.
Future<bool> _initFirebase() async {
  if (Platform.isLinux) return false; // no Linux implementation
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return true;
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
    return false;
  }
}

class BastakLeadsApp extends StatelessWidget {
  final SettingsService settings;
  final LeadRepository repo;
  final AuthService auth;
  final NotificationService notifications;
  final bool firebaseReady;

  const BastakLeadsApp({
    super.key,
    required this.settings,
    required this.repo,
    required this.auth,
    required this.notifications,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        repo: repo,
        settings: settings,
        notifications: notifications,
        firebaseReady: firebaseReady,
      ),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Bastak Leads',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            home: AuthGate(auth: auth, firebaseReady: firebaseReady),
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
  final bool firebaseReady;
  const AuthGate({super.key, required this.auth, required this.firebaseReady});

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

  /// Called when the login screen authenticates a Firestore user.
  void _onLoggedIn(AppUser user) {
    context.read<AppState>().setCurrentUser(user);
    _onUnlocked();
  }

  /// The non-Firebase fallback (Windows/Linux, or offline) keeps the old local
  /// PIN lock. There's no per-user identity there, so the local operator is
  /// treated as an admin — preserving the app's prior single-user behaviour.
  void _onLocalUnlocked() {
    context.read<AppState>().setCurrentUser(const AppUser(
          name: 'This device',
          email: '',
          role: UserRole.admin,
          active: true,
        ));
    _onUnlocked();
  }

  void _lock() {
    if (!_unlocked) return;
    _idleTimer?.cancel();
    context.read<AppState>().logout();
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
      // Firebase available → per-user email + PIN login against Firestore.
      // Otherwise fall back to the local PIN lock (single-user, treated admin).
      return widget.firebaseReady
          ? LoginScreen(users: UserRepository(), onLoggedIn: _onLoggedIn)
          : LockScreen(auth: widget.auth, onUnlocked: _onLocalUnlocked);
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
