import 'package:flutter/material.dart';

import 'widgets/brand_logo.dart';
import 'widgets/version_text.dart';

/// Branded launch screen shown on startup across every platform (Windows,
/// macOS, Android) — a single implementation instead of per-OS native splash
/// configs. Fades the stacked logo in, holds briefly, then calls [onDone].
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF101410) : Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(
              parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            ),
            child: const BrandLogo.stacked(height: 150),
          ),
        ),
      ),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.only(bottom: 28),
        child: VersionText(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
