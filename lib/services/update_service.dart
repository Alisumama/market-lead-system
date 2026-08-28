import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

/// One release as described by the Firestore `config/appVersion` manifest.
class UpdateInfo {
  final String version; // e.g. "2.1.5"
  final String url; // GitHub Release asset (setup.exe)
  final String? sha256; // optional integrity check of the download
  final bool mandatory; // if true, the user can't dismiss the prompt
  final String notes; // what's new

  const UpdateInfo({
    required this.version,
    required this.url,
    this.sha256,
    this.mandatory = false,
    this.notes = '',
  });
}

/// Why an update check found nothing. A manifest that hasn't been published is
/// reported separately from genuinely being up to date: the two used to be
/// indistinguishable (both a null [UpdateInfo]), so a missing `config/appVersion`
/// document looked exactly like a working "no update available" result.
enum UpdateStatus {
  /// A newer release is available; [UpdateCheck.info] carries it.
  available,

  /// The manifest was read and the running build is current.
  upToDate,

  /// No usable manifest exists yet — the document is missing, or lacks the
  /// version/url fields. A configuration problem, not a verdict on the build.
  noManifest,

  /// Self-update doesn't apply on this platform.
  unsupported,
}

/// The outcome of an update check.
class UpdateCheck {
  final UpdateStatus status;

  /// Set only when [status] is [UpdateStatus.available].
  final UpdateInfo? info;

  const UpdateCheck(this.status, {this.info});
}

/// Self-update for the Windows desktop build.
///
/// The Windows app has no Firebase SDK (see main._initFirebase), so it reads the
/// version manifest from Firestore over its plain **REST** endpoint — the
/// `config/appVersion` document, which needs a public read rule. The installer
/// binary is a GitHub Release asset. On update we download it, verify the
/// SHA-256, then hand off to the existing Inno Setup installer silently: because
/// the installer keeps a stable AppId it upgrades in place and relaunches us.
class UpdateService {
  UpdateService({http.Client? client, String projectId = 'baskat-leads'})
      : _client = client ?? http.Client(),
        _manifestUrl = 'https://firestore.googleapis.com/v1/projects/'
            '$projectId/databases/(default)/documents/config/appVersion';

  final http.Client _client;
  final String _manifestUrl;

  /// Self-update only makes sense for the packaged Windows installer build.
  bool get supported => Platform.isWindows;

  /// Reads the manifest and reports whether it describes a version newer than
  /// the running app. Distinguishes "no manifest published" from "up to date"
  /// so the UI can tell the user which it is. Throws on network/parse errors so
  /// a *manual* check can report the failure; the automatic check swallows those.
  Future<UpdateCheck> checkForUpdate() async {
    if (!supported) return const UpdateCheck(UpdateStatus.unsupported);
    final latest = await fetchManifest();
    if (latest == null) return const UpdateCheck(UpdateStatus.noManifest);
    final current = (await PackageInfo.fromPlatform()).version;
    return isNewer(latest.version, current)
        ? UpdateCheck(UpdateStatus.available, info: latest)
        : const UpdateCheck(UpdateStatus.upToDate);
  }

  /// Fetches and parses the Firestore REST manifest, or null if the document
  /// doesn't exist yet.
  Future<UpdateInfo?> fetchManifest() async {
    final resp = await _client.get(Uri.parse(_manifestUrl));
    if (resp.statusCode == 404) return null; // no manifest published yet
    if (resp.statusCode != 200) {
      throw HttpException('Manifest fetch failed (${resp.statusCode})');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final fields = body['fields'] as Map<String, dynamic>?;
    if (fields == null) return null;

    String str(String k) =>
        (fields[k] as Map<String, dynamic>?)?['stringValue'] as String? ?? '';
    bool flag(String k) =>
        (fields[k] as Map<String, dynamic>?)?['booleanValue'] as bool? ?? false;

    final version = str('version');
    final url = str('url');
    if (version.isEmpty || url.isEmpty) return null;
    final hash = str('sha256');
    return UpdateInfo(
      version: version,
      url: url,
      sha256: hash.isEmpty ? null : hash,
      mandatory: flag('mandatory'),
      notes: str('notes'),
    );
  }

  /// Downloads the installer to a temp file, reporting fractional progress, and
  /// verifies the SHA-256 when the manifest supplies one. Returns the file.
  Future<File> download(UpdateInfo info,
      {void Function(double fraction)? onProgress}) async {
    final req = http.Request('GET', Uri.parse(info.url));
    final resp = await _client.send(req);
    if (resp.statusCode != 200) {
      throw HttpException('Download failed (${resp.statusCode})');
    }
    final total = resp.contentLength ?? 0;
    final dir = Directory.systemTemp;
    final file =
        File(p.join(dir.path, 'bastak_leads-${info.version}-setup.exe'));
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }

    final want = info.sha256;
    if (want != null && want.isNotEmpty) {
      final got = sha256.convert(await file.readAsBytes()).toString();
      if (got.toLowerCase() != want.toLowerCase()) {
        await file.delete();
        throw const FormatException(
            'Downloaded installer failed its integrity check');
      }
    }
    return file;
  }

  /// Launches the installer silently and quits so it can replace the running
  /// exe. Inno's [Run]/WizardSilent entry relaunches the app afterwards.
  Future<Never> installAndExit(File installer) async {
    await Process.start(
      installer.path,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  void dispose() => _client.close();

  /// True when [remote] is a strictly higher semantic version than [current].
  /// Compares the numeric major.minor.patch, ignoring any build/tag suffix.
  static bool isNewer(String remote, String current) {
    final r = _parts(remote);
    final c = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (r[i] != c[i]) return r[i] > c[i];
    }
    return false;
  }

  static List<int> _parts(String v) {
    final core = v.trim().split('+').first.split('-').first;
    final nums = core
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }
}
