import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../widgets/brand_logo.dart';
import '../widgets/version_text.dart';

/// First screen the user sees. On first ever launch it asks them to create a
/// local PIN; afterwards it offers biometric unlock (Windows Hello / Touch ID /
/// fingerprint) with PIN as the always-available fallback. Fully local.
class LockScreen extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onUnlocked;
  const LockScreen(
      {super.key, required this.auth, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _setupMode = false;
  bool _loading = true;
  bool _canBiometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final needsSetup = await widget.auth.needsSetup;
    final canBio = needsSetup ? false : await widget.auth.canUseBiometrics();
    setState(() {
      _setupMode = needsSetup;
      _canBiometric = canBio;
      _loading = false;
    });
    if (canBio) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final ok = await widget.auth.authenticateBiometric();
    if (ok && mounted) widget.onUnlocked();
  }

  Future<void> _createPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }
    if (pin != _confirmCtrl.text.trim()) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    await widget.auth.setPin(pin);
    widget.onUnlocked();
  }

  Future<void> _verifyPin() async {
    final ok = await widget.auth.verifyPin(_pinCtrl.text.trim());
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN');
      _pinCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandLogo.stacked(height: 96),
                      const SizedBox(height: 24),
                      Text(
                        _setupMode
                            ? 'Create a PIN to protect your leads on this device'
                            : 'Enter your PIN to unlock',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        onSubmitted: (_) =>
                            _setupMode ? null : _verifyPin(),
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (_setupMode) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Confirm PIN',
                            prefixIcon: Icon(Icons.lock_reset),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: scheme.error)),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _setupMode ? _createPin : _verifyPin,
                          child: Text(_setupMode ? 'Create PIN' : 'Unlock'),
                        ),
                      ),
                      if (_canBiometric) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _tryBiometric,
                          icon: const Icon(Icons.fingerprint),
                          label: Text(
                              'Use ${widget.auth.biometricLabel()}'),
                        ),
                      ],
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
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }
}
