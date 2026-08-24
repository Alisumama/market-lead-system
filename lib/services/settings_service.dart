import 'dart:convert';

import '../scoring/keyword_scorer.dart';
import 'secure_kv.dart';

/// Persists user preferences and the (optional) local PIN. Uses OS-backed
/// secure storage where available (Keychain / Keystore / DPAPI), falling back
/// to a local file on platforms where it isn't (e.g. unsigned macOS). Either
/// way everything stays on the device — nothing is sent anywhere.
class SettingsService {
  final SecureKv _store;
  SettingsService([SecureKv? store]) : _store = store ?? SecureKv();

  static const _kAutoRefreshHourly = 'auto_refresh_hourly';
  static const _kFreshDays = 'fresh_days';
  static const _kLeadView = 'lead_view';
  static const _kLastBatchAt = 'last_batch_at';
  static const _kBackground = 'background_refresh';
  static const _kDarkMode = 'dark_mode';
  static const _kNotifEnabled = 'notif_enabled';
  static const _kNotifAfterRefresh = 'notif_after_refresh';
  static const _kNotifOnlyNew = 'notif_only_new';
  static const _kNotifMinScore = 'notif_min_score';
  static const _kScoringConfig = 'scoring_config_v2';
  static const _kRejectStats = 'reject_stats_v1';
  static const _kRuleProfiles = 'rule_profiles_v1';
  static const _kFacility = 'vocab_facility';
  static const _kIntent = 'vocab_intent';
  static const _kNegative = 'vocab_negative';
  static const _kCutoff = 'relevance_cutoff';
  static const _kPinHash = 'pin_hash';
  static const _kBiometric = 'biometric_enabled';
  static const _kLockOnBackground = 'lock_on_background';
  static const _kAutoLockMinutes = 'auto_lock_minutes';

  Future<bool> autoRefreshHourly() async =>
      (await _store.read(key: _kAutoRefreshHourly) ?? 'true') == 'true';
  Future<void> setAutoRefreshHourly(bool v) =>
      _store.write(key: _kAutoRefreshHourly, value: '$v');

  Future<int> freshDays() async =>
      int.tryParse(await _store.read(key: _kFreshDays) ?? '') ?? 90;
  Future<void> setFreshDays(int v) =>
      _store.write(key: _kFreshDays, value: '$v');

  /// 'list' or 'grid'
  Future<String> leadView() async =>
      await _store.read(key: _kLeadView) ?? 'list';
  Future<void> setLeadView(String v) =>
      _store.write(key: _kLeadView, value: v);

  /// UTC ISO timestamp marking the start of the most recent fetch that added
  /// leads — anything collected at/after it is "new". Null until the first
  /// productive fetch.
  Future<String?> lastBatchAt() => _store.read(key: _kLastBatchAt);
  Future<void> setLastBatchAt(String iso) =>
      _store.write(key: _kLastBatchAt, value: iso);

  Future<bool> backgroundEnabled() async =>
      (await _store.read(key: _kBackground) ?? 'false') == 'true';
  Future<void> setBackgroundEnabled(bool v) =>
      _store.write(key: _kBackground, value: '$v');

  // ---- Notifications ----
  Future<bool> notifEnabled() async =>
      (await _store.read(key: _kNotifEnabled) ?? 'false') == 'true';
  Future<void> setNotifEnabled(bool v) =>
      _store.write(key: _kNotifEnabled, value: '$v');

  Future<bool> notifAfterRefresh() async =>
      (await _store.read(key: _kNotifAfterRefresh) ?? 'true') == 'true';
  Future<void> setNotifAfterRefresh(bool v) =>
      _store.write(key: _kNotifAfterRefresh, value: '$v');

  Future<bool> notifOnlyNew() async =>
      (await _store.read(key: _kNotifOnlyNew) ?? 'true') == 'true';
  Future<void> setNotifOnlyNew(bool v) =>
      _store.write(key: _kNotifOnlyNew, value: '$v');

  Future<int> notifMinScore() async =>
      int.tryParse(await _store.read(key: _kNotifMinScore) ?? '') ?? 0;
  Future<void> setNotifMinScore(int v) =>
      _store.write(key: _kNotifMinScore, value: '$v');

  /// null = follow system.
  Future<bool?> darkMode() async {
    final v = await _store.read(key: _kDarkMode);
    if (v == null) return null;
    return v == 'true';
  }

  Future<void> setDarkMode(bool? v) => v == null
      ? _store.delete(key: _kDarkMode)
      : _store.write(key: _kDarkMode, value: '$v');

  // ---- Scoring / rules engine (stored as one JSON blob) ----
  Future<ScoringConfig> scoringConfig() async {
    final raw = await _store.read(key: _kScoringConfig);
    if (raw == null || raw.isEmpty) {
      // Migrate the old piecemeal vocab keys if present.
      final legacyFac = await _store.read(key: _kFacility);
      if (legacyFac != null) {
        return ScoringConfig(
          facilityTerms:
              await _readList(_kFacility, KeywordScorer.defaultFacilityTerms),
          intentTerms:
              await _readList(_kIntent, KeywordScorer.defaultIntentTerms),
          negativeTerms:
              await _readList(_kNegative, KeywordScorer.defaultNegativeTerms),
          relevanceCutoff:
              int.tryParse(await _store.read(key: _kCutoff) ?? '') ?? 4,
        );
      }
      return const ScoringConfig();
    }
    try {
      return ScoringConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ScoringConfig();
    }
  }

  Future<void> saveScoringConfig(ScoringConfig c) async {
    await _store.write(key: _kScoringConfig, value: jsonEncode(c.toJson()));
  }

  Future<void> resetScoringConfig() async {
    await _store.delete(key: _kScoringConfig);
  }

  // ---- rejection stats (last pipeline run) ----

  Future<void> saveRejectStats(Map<String, dynamic> json) =>
      _store.write(key: _kRejectStats, value: jsonEncode(json));

  Future<Map<String, dynamic>?> rejectStats() async {
    final raw = await _store.read(key: _kRejectStats);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  // ---- named rule profiles ----

  Future<List<RuleProfile>> ruleProfiles() async {
    final raw = await _store.read(key: _kRuleProfiles);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RuleProfile.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRuleProfiles(List<RuleProfile> profiles) => _store.write(
      key: _kRuleProfiles,
      value: jsonEncode([for (final p in profiles) p.toJson()]));

  Future<List<String>> _readList(String key, List<String> fallback) async {
    final raw = await _store.read(key: key);
    if (raw == null || raw.isEmpty) return fallback;
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return fallback;
    }
  }

  // ---- Auth ----
  Future<String?> pinHash() => _store.read(key: _kPinHash);
  Future<void> setPinHash(String hash) =>
      _store.write(key: _kPinHash, value: hash);
  Future<void> clearPin() => _store.delete(key: _kPinHash);

  Future<bool> biometricEnabled() async =>
      (await _store.read(key: _kBiometric) ?? 'true') == 'true';
  Future<void> setBiometricEnabled(bool v) =>
      _store.write(key: _kBiometric, value: '$v');

  Future<bool> lockOnBackground() async =>
      (await _store.read(key: _kLockOnBackground) ?? 'true') == 'true';
  Future<void> setLockOnBackground(bool v) =>
      _store.write(key: _kLockOnBackground, value: '$v');

  /// Minutes of inactivity before the app auto-locks. 0 = only lock on
  /// backgrounding (no idle timer).
  Future<int> autoLockMinutes() async =>
      int.tryParse(await _store.read(key: _kAutoLockMinutes) ?? '') ?? 5;
  Future<void> setAutoLockMinutes(int v) =>
      _store.write(key: _kAutoLockMinutes, value: '$v');
}
