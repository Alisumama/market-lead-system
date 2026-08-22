import 'dart:ui';

import 'package:flutter/material.dart';

import 'brand_logo.dart';

/// Shared bits for the top app bars.
///
/// The app bars float over the scrolling list, so a fully transparent bar lets
/// content bleed through and clash with the title. These give the bar a
/// frosted-glass look: a translucent fill plus a blur of whatever scrolls
/// behind it — readable, but still shows there's content underneath.

const double _kMobileBreakpoint = 800;

Color translucentBarColor(BuildContext context) =>
    Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.72);

/// A blurred backdrop to drop into a SliverAppBar's [flexibleSpace].
Widget frostedFlexibleSpace() => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: const SizedBox.expand(),
      ),
    );

/// The Bastak mark, shown as the app-bar leading on phones so the brand is
/// present there too (on desktop the nav rail already shows the full logo).
/// Returns null on wide layouts.
Widget? mobileBrandLeading(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= _kMobileBreakpoint) return null;
  return const Padding(
    padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
    child: BrandLogo.mark(height: 26),
  );
}
