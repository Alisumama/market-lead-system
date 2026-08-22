import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small key/value store that prefers the OS-backed secure storage
/// (Keychain / Keystore / DPAPI) but transparently falls back to a local file
/// when the platform's secure store is unavailable.
///
/// Why: on an *unsigned* macOS build, flutter_secure_storage throws
/// `errSecMissingEntitlement (-34018)` because the Keychain needs a signed app
/// with the Keychain-Sharing entitlement. Rather than making the whole app
/// unusable there, we degrade to a JSON file in the app-support directory.
/// Android, Windows, and signed macOS builds keep using real secure storage.
class SecureKv {
  final FlutterSecureStorage _secure;
  SecureKv([FlutterSecureStorage? secure])
      : _secure = secure ?? const FlutterSecureStorage();

  bool? _secureWorks; // null = untested, true/false = known
  Map<String, String>? _cache;

  /// Decide the backend once by probing *writability*, not readability.
  /// On unsigned macOS, Keychain reads succeed (returning null for a missing
  /// item) while writes fail with -34018 — so inferring from a read would
  /// wrongly pick Keychain and silently lose everything we write. A probe
  /// write+delete tells us the truth.
  Future<bool> _usableSecure() async {
    if (_secureWorks != null) return _secureWorks!;
    try {
      const probe = '__bastak_probe__';
      await _secure.write(key: probe, value: '1');
      await _secure.delete(key: probe);
      _secureWorks = true;
    } catch (_) {
      _secureWorks = false;
    }
    return _secureWorks!;
  }

  Future<String?> read({required String key}) async {
    if (await _usableSecure()) {
      try {
        return await _secure.read(key: key);
      } catch (_) {
        _secureWorks = false;
      }
    }
    return (await _file())[key];
  }

  Future<void> write({required String key, required String value}) async {
    if (await _usableSecure()) {
      try {
        await _secure.write(key: key, value: value);
        return;
      } catch (_) {
        _secureWorks = false;
      }
    }
    final map = await _file();
    map[key] = value;
    await _persist(map);
  }

  Future<void> delete({required String key}) async {
    if (await _usableSecure()) {
      try {
        await _secure.delete(key: key);
        return;
      } catch (_) {
        _secureWorks = false;
      }
    }
    final map = await _file();
    map.remove(key);
    await _persist(map);
  }

  // ---- file fallback ----
  Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    return File(p.join(dir.path, 'settings.json'));
  }

  Future<Map<String, String>> _file() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _fallbackFile();
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString());
        _cache = (data as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } else {
        _cache = {};
      }
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _persist(Map<String, String> map) async {
    _cache = map;
    try {
      final f = await _fallbackFile();
      await f.writeAsString(jsonEncode(map));
    } catch (_) {
      // In-memory cache still serves this session.
    }
  }
}
