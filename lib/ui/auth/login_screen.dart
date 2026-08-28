import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/app_user.dart';
import '../../data/user_repository.dart';
import '../widgets/brand_logo.dart';
import '../widgets/version_text.dart';

/// Per-user sign-in against the Firestore `Users` collection: enter email + PIN,
/// matched to an active user. Replaces the old single local-PIN lock when
/// Firebase is available. Users are provisioned by an admin (Users tab / seed),
/// so there is no first-run "create a PIN" step here.
class LoginScreen extends StatefulWidget {
  final UserRepository users;
  final ValueChanged<AppUser> onLoggedIn;
  const LoginScreen(
      {super.key, required this.users, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pin = TextEditingController();

  bool _busy = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _login() async {
    final email = _email.text.trim();
    final pin = _pin.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    if (pin.length < 4) {
      setState(() => _error = 'Enter your PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.users.byEmail(email);
      if (user == null || !user.verifyPin(pin)) {
        setState(() => _error = 'Incorrect email or PIN');
        return;
      }
      if (!user.active) {
        setState(() => _error = 'This account is inactive. Contact an admin.');
        return;
      }
      widget.onLoggedIn(user);
    } catch (e) {
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo.stacked(height: 96),
                const SizedBox(height: 24),
                Text(
                  'Sign in to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    prefixIcon: Icon(Icons.pin_outlined),
                    counterText: '',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 28),
                const VersionText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }
}
