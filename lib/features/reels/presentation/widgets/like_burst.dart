import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

// ring + sparks + heart, all driven by one controller
class LikeBurst extends StatefulWidget {
  const LikeBurst({
    required this.at,
    required this.onFinished,
    super.key,
  });

  final Offset at;
  final VoidCallback onFinished;

  @override
  State<LikeBurst> createState() => _LikeBurstState();
}

class _LikeBurstState extends State<LikeBurst> with TickerProviderStateMixin {
  static const double _box = 160;

  // underdamped, so the heart overshoots and wobbles into place
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 320, damping: 13);

  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  // unbounded: the spring runs past 1 on its way to settling
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
  );

  late final double _tilt = (math.Random().nextDouble() - 0.5) * 0.5;

  @override
  void initState() {
    super.initState();
    _t.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
    unawaited(_t.forward());
    unawaited(_pop.animateWith(SpringSimulation(_spring, 0, 1, 0)));
  }

  @override
  void dispose() {
    _t.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.at.dx - _box / 2,
      top: widget.at.dy - _box / 2,
      width: _box,
      height: _box,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_t, _pop]),
          builder: (context, heart) {
            final v = _t.value;
            final pop = math.max(0, _pop.value).toDouble();
            final fade = v < 0.7 ? 1.0 : 1 - (v - 0.7) / 0.3;
            return CustomPaint(
              painter: _SparkPainter(progress: v),
              child: Center(
                child: Opacity(
                  opacity: fade.clamp(0, 1),
                  child: Transform.rotate(
                    angle: _tilt,
                    child: Transform.scale(scale: pop, child: heart),
                  ),
                ),
              ),
            );
          },
          child: const Icon(
            Icons.favorite_rounded,
            size: 84,
            color: AppColors.rose,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.progress});

  final double progress;

  static const int _sparks = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final grow = Curves.easeOut.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);

    canvas.drawCircle(
      c,
      20 + grow * 56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * fade
        ..color = AppColors.lime.withOpacity(0.8 * fade),
    );

    final dot = Paint()..color = AppColors.teal.withOpacity(fade);
    for (var i = 0; i < _sparks; i++) {
      final a = i * 2 * math.pi / _sparks;
      final r = 30 + grow * 46;
      canvas.drawCircle(
        c + Offset(math.cos(a) * r, math.sin(a) * r),
        3.5 * fade,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
