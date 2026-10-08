import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

// mid-black base with two slow drifting glows, a shine sweep and faint
// crt scanlines
class GlowBackground extends StatefulWidget {
  const GlowBackground({
    required this.primaryGlow,
    required this.secondaryGlow,
    required this.child,
    super.key,
  });

  final Color primaryGlow;
  final Color secondaryGlow;
  final Widget child;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // separate layers so the moving glow never repaints the scanlines or
    // the content on top
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: widget.primaryGlow),
            duration: const Duration(milliseconds: 700),
            builder: (context, primary, _) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: widget.secondaryGlow),
              duration: const Duration(milliseconds: 700),
              builder: (context, secondary, _) => CustomPaint(
                painter: _GlowPainter(
                  animation: _controller,
                  primary: primary ?? widget.primaryGlow,
                  secondary: secondary ?? widget.secondaryGlow,
                ),
              ),
            ),
          ),
        ),
        const RepaintBoundary(child: CustomPaint(painter: _ScanlinePainter())),
        RepaintBoundary(child: widget.child),
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.animation,
    required this.primary,
    required this.secondary,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * 2 * math.pi;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.signalBase);

    final r = size.shortestSide;
    _glow(
      canvas,
      Offset(
        size.width * (0.5 + 0.28 * math.sin(t)),
        size.height * (0.38 + 0.08 * math.cos(t * 2)),
      ),
      r * 0.75,
      primary.withOpacity(0.30),
    );
    _glow(
      canvas,
      Offset(
        size.width * (0.5 - 0.3 * math.sin(t + 1.2)),
        size.height * (0.52 + 0.1 * math.sin(t * 2 + 0.5)),
      ),
      r * 0.65,
      secondary.withOpacity(0.22),
    );

    final sweep = (animation.value * 2) % 1.0;
    final shineRect = Rect.fromLTWH(
      -size.width + sweep * size.width * 3,
      0,
      size.width,
      size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0),
            Colors.white.withOpacity(0.045),
            Colors.white.withOpacity(0),
          ],
        ).createShader(shineRect),
    );
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withOpacity(0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final line = Paint()..color = Colors.black.withOpacity(0.18);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => false;
}
