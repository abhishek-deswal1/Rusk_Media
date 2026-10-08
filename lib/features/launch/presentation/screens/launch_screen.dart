import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({required this.next, super.key});

  // what to show once the intro ends; the app wires this up so the launch
  // feature doesn't reach into another feature
  final WidgetBuilder next;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  // the whole intro hangs off one timeline
  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  Animation<double> _span(
    double from,
    double to, [
    Curve curve = Curves.linear,
  ]) =>
      CurvedAnimation(
        parent: _timeline,
        curve: Interval(from, to, curve: curve),
      );

  late final _glowRise = _span(0, 0.55, Curves.easeOutCubic);
  late final _tileDrop = _span(0.05, 0.38, Curves.easeOutBack);
  late final _glyphTrace = _span(0.3, 0.5, Curves.easeInOut);
  late final _glyphFill = _span(0.5, 0.58);
  late final _tagline = _span(0.72, 0.86, Curves.easeOut);
  late final _settle = _span(0.88, 1, Curves.easeIn);

  @override
  void initState() {
    super.initState();
    _timeline.addStatusListener(_onTimeline);
    unawaited(_timeline.forward());
  }

  void _onTimeline(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, __, ___) => widget.next(context),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AnimatedBuilder(
        animation: _timeline,
        builder: (context, _) {
          final settle = _settle.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              _RisingGlow(progress: _glowRise.value),
              Opacity(
                opacity: 1 - settle,
                child: Transform.scale(
                  scale: 1 - settle * 0.08,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, (1 - _tileDrop.value) * -160),
                        child: Transform.rotate(
                          angle: (1 - _tileDrop.value) * -0.35,
                          child: _Tile(
                            trace: _glyphTrace.value,
                            fill: _glyphFill.value,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _Wordmark(progress: _timeline.value),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: _tagline.value,
                        child: CustomText(
                          AppStrings.launchLine,
                          semanticLocator: 'launch_line',
                          textStyle: AppTextStyles.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RisingGlow extends StatelessWidget {
  const _RisingGlow({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(0.6, 1.4 - progress * 1.2),
      child: Opacity(
        opacity: progress * 0.9,
        child: Container(
          width: 420,
          height: 420,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.lime.withOpacity(0.22),
                AppColors.teal.withOpacity(0.08),
                AppColors.ink.withOpacity(0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.trace, required this.fill});

  final double trace;
  final double fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.lime.withOpacity(0.35),
            blurRadius: 36,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: CustomPaint(painter: _GlyphPainter(trace: trace, fill: fill)),
    );
  }
}

// play glyph: the outline is traced first, then it fills in
class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.trace, required this.fill});

  final double trace;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final glyph = Path()
      ..moveTo(w * 0.38, w * 0.28)
      ..lineTo(w * 0.74, w * 0.5)
      ..lineTo(w * 0.38, w * 0.72)
      ..close();

    if (fill > 0) {
      canvas.drawPath(
        glyph,
        Paint()..color = AppColors.ink.withOpacity(fill),
      );
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ink;
    for (final metric in glyph.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * trace), outline);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.trace != trace || oldDelegate.fill != fill;
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.progress});

  final double progress;

  static const String _word = 'rusk media';
  static const double _start = 0.45;
  static const double _end = 0.75;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.display;
    const step = (_end - _start) / _word.length;
    return Semantics(
      label: AppStrings.appName,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _word.length; i++)
              Builder(
                builder: (context) {
                  final from = _start + i * step;
                  final t = ((progress - from) / (step * 3)).clamp(0.0, 1.0);
                  final eased = Curves.easeOutCubic.transform(t);
                  return Opacity(
                    opacity: eased,
                    child: Transform.translate(
                      offset: Offset(0, (1 - eased) * 14),
                      child: CustomText(
                        _word[i],
                        semanticLocator: 'launch_wordmark_letter',
                        textStyle: i < 4
                            ? style
                            : style.copyWith(color: AppColors.lime),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
