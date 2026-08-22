import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A cached featured image with a branded placeholder/fallback. Used in the
/// grid and (as a thumbnail) list views. Falls back to a tinted grain glyph
/// when there's no image or it fails to load.
class LeadImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double iconSize;

  const LeadImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize = 30,
  });

  bool get hasImage => url.trim().startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (!hasImage) return _fallback(context);
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => _fallback(context, shimmer: true),
      errorWidget: (context, url, error) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context, {bool shimmer = false}) {
    return Container(
      width: width,
      height: height,
      color: AppTheme.brandGreen.withValues(alpha: shimmer ? 0.06 : 0.10),
      alignment: Alignment.center,
      child: shimmer
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.grain,
              size: iconSize,
              color: AppTheme.brandGreen.withValues(alpha: 0.55)),
    );
  }
}
