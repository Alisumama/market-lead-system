import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the app version + build number at runtime (from pubspec's `version:`
/// on each platform) so it never needs hand-updating. Cached after first load.
class AppVersion {
  static PackageInfo? _cached;

  static Future<PackageInfo> load() async =>
      _cached ??= await PackageInfo.fromPlatform();

  /// e.g. "v1.0.0 (build 1)"
  static String format(PackageInfo info) =>
      'v${info.version} (build ${info.buildNumber})';
}

/// A tiny label showing the formatted version string. Renders empty space
/// until the info resolves, then fades it in.
class VersionText extends StatelessWidget {
  final TextStyle? style;
  final TextAlign textAlign;
  const VersionText({super.key, this.style, this.textAlign = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    final base = style ??
        TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return FutureBuilder<PackageInfo>(
      future: AppVersion.load(),
      builder: (context, snap) {
        final text = snap.hasData ? AppVersion.format(snap.data!) : '';
        return AnimatedOpacity(
          opacity: text.isEmpty ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Text(text.isEmpty ? ' ' : text,
              textAlign: textAlign, style: base),
        );
      },
    );
  }
}
