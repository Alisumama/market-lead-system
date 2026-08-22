import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which Bastak lockup to render.
enum BrandLogoVariant { horizontal, stacked, mark }

/// Renders the official Bastak SVG logo, automatically choosing the white
/// knockout version on dark backgrounds. One widget for headers, splash, login
/// and about — always crisp (vector) at any size.
class BrandLogo extends StatelessWidget {
  final BrandLogoVariant variant;
  final double? height;
  final double? width;

  /// Force a colour scheme instead of following the theme brightness. Use
  /// `true` on an intentionally-dark surface (e.g. a green splash plate).
  final bool? white;

  const BrandLogo({
    super.key,
    this.variant = BrandLogoVariant.horizontal,
    this.height,
    this.width,
    this.white,
  });

  const BrandLogo.horizontal({super.key, this.height, this.width, this.white})
      : variant = BrandLogoVariant.horizontal;
  const BrandLogo.stacked({super.key, this.height, this.width, this.white})
      : variant = BrandLogoVariant.stacked;
  const BrandLogo.mark({super.key, this.height, this.width, this.white})
      : variant = BrandLogoVariant.mark;

  @override
  Widget build(BuildContext context) {
    final useWhite =
        white ?? (Theme.of(context).brightness == Brightness.dark);
    final base = switch (variant) {
      BrandLogoVariant.horizontal => 'bastak-logo-horizontal',
      BrandLogoVariant.stacked => 'bastak-logo-stacked',
      BrandLogoVariant.mark => 'bastak-mark',
    };
    final asset = 'assets/logo/$base${useWhite ? '-white' : ''}.svg';
    return SvgPicture.asset(
      asset,
      height: height,
      width: width,
      fit: BoxFit.contain,
      semanticsLabel: 'Bastak Instruments',
    );
  }
}
