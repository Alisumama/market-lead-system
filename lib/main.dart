import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/lead_repository.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/auth/lock_screen.dart';
import 'ui/home/home_shell.dart';
import 'ui/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

/// Decides between the lock screen and the app, and initialises AppState once
/// the user is authenticated.
class AuthGate extends StatefulWidget {
  final AuthService auth;
  const AuthGate({super.key, required this.auth});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _splashDone = false;
  bool _unlocked = false;
  bool _initStarted = false;

  void _onUnlocked() {
    setState(() => _unlocked = true);
    if (!_initStarted) {
      _initStarted = true;
      context.read<AppState>().init();
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
    return const HomeShell();
  }
}
