import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_service.dart';

enum AuthMethod { biometric, pin, none }

/// Local-machine authentication. No server, no accounts. Two layers:
///   1. Device biometrics / OS credential (Windows Hello, macOS Touch ID,
///      Android fingerprint/face) via local_auth, when the device supports it.
///   2. A local PIN the user sets on first launch, hashed (sha-256 + salt) in
///      secure storage — used as the fallback and always available.
class AuthService {
  final SettingsService settings;
  final LocalAuthentication _localAuth;

  AuthService(this.settings, [LocalAuthentication? localAuth])
      : _localAuth = localAuth ?? LocalAuthentication();

  static const _salt = 'bastak-leads-v1';

  Future<bool> hasPin() async => (await settings.pinHash()) != null;

  /// True on first ever launch — no PIN configured yet.
  Future<bool> get needsSetup async => !await hasPin();

  Future<bool> canUseBiometrics() async {
    try {
      if (!await settings.biometricEnabled()) return false;
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && (canCheck || await _hasDeviceCredential());
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasDeviceCredential() async {
    try {
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Bastak Leads',
        persistAcrossBackgrounding: true,
        // Allow the OS password/PIN as a fallback where supported.
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }

  String _hash(String pin) =>
      sha256.convert(utf8.encode('$_salt:$pin')).toString();

  Future<void> setPin(String pin) => settings.setPinHash(_hash(pin));

  Future<bool> verifyPin(String pin) async {
    final stored = await settings.pinHash();
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  Future<void> changePin(String newPin) => setPin(newPin);
  Future<void> disablePin() => settings.clearPin();

  /// Platform label for the biometric prompt (best-effort, cosmetic).
  String biometricLabel() {
    if (Platform.isMacOS) return 'Touch ID';
    if (Platform.isWindows) return 'Windows Hello';
    if (Platform.isAndroid) return 'Fingerprint / Face';
    return 'Device unlock';
  }
}
