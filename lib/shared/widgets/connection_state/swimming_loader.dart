import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rusk_media/core/constants/app_images.dart';
import 'package:rusk_media/core/logger/app_logger.dart';

// thin water line with an animated boy swimming across it. frames are
// decoded once at draw size and blended, so motion runs at display refresh
// instead of the source's 30fps
class SwimmingLoader extends StatefulWidget {
  const SwimmingLoader({
    super.key,
    this.waterHeight = 3,
    this.boyHeight = 40,
    this.lapDuration = const Duration(milliseconds: 4500),
    this.playbackSpeed = 1.5,
    this.waterColor = const Color(0xFF1E88E5),
    this.deepWaterColor = const Color(0xFF0D47A1),
    this.shineColor = const Color(0xFFB3E5FC),
  });

  final double waterHeight;
  final double boyHeight;
  final Duration lapDuration;
  final double playbackSpeed;
  final Color waterColor;
  final Color deepWaterColor;
  final Color shineColor;

  @override
  State<SwimmingLoader> createState() => _SwimmingLoaderState();
}

class _SwimmingLoaderState extends State<SwimmingLoader>
    with SingleTickerProviderStateMixin {
  static const double _frameAspect = 360 / 194;
  static const double _sourceFps = 30;

  final ValueNotifier<Duration> _clock = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker((elapsed) => _clock.value = elapsed);

  List<ui.Image> _frames = const [];
  double? _decodedForDpr;
  int _decodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_ticker.start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_decodedForDpr != dpr) {
      _decodedForDpr = dpr;
      unawaited(_loadFrames(dpr));
    }
  }

  // decoded once per draw height and kept for the app's life: the loading
  // screen and every buffering bar share the same frames, so showing the
  // loader again never decodes again
  static final Map<int, Future<List<ui.Image>>> _decoded = {};

  Future<void> _loadFrames(double dpr) async {
    // a dpr change can start a second load; only the newest one may land
    final generation = ++_decodeGeneration;
    final height = (widget.boyHeight * dpr).round();
    final bundle = DefaultAssetBundle.of(context);
    final List<ui.Image> frames;
    try {
      frames = await (_decoded[height] ??= _decode(bundle, height));
    } on Object catch (e) {
      // drop the failed attempt so the next mount can try again
      _decoded.remove(height)?.ignore();
      AppLogger.logWarning('swimming loader decode failed: $e');
      return;
    }
    if (!mounted || generation != _decodeGeneration) return;
    setState(() => _frames = frames);
  }

  static Future<List<ui.Image>> _decode(AssetBundle bundle, int height) async {
    final frames = <ui.Image>[];
    try {
      final data = await bundle.load(AppWebpImages.swimmingBoy);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetHeight: height,
      );
      for (var i = 0; i < codec.frameCount; i++) {
        frames.add((await codec.getNextFrame()).image);
      }
      codec.dispose();
      return frames;
    } on Object {
      for (final frame in frames) {
        frame.dispose();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height =
        widget.boyHeight * _SwimPainter.bellyLine + widget.waterHeight + 10;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SwimPainter(
            clock: _clock,
            frames: _frames,
            frameRate: _sourceFps * widget.playbackSpeed,
            lapSeconds: widget.lapDuration.inMicroseconds / 1e6,
            boyHeight: widget.boyHeight,
            boyWidth: widget.boyHeight * _frameAspect,
            waterHeight: widget.waterHeight,
            waterColor: widget.waterColor,
            deepWaterColor: widget.deepWaterColor,
            shineColor: widget.shineColor,
          ),
        ),
      ),
    );
  }
}

class _SwimPainter extends CustomPainter {
  _SwimPainter({
    required this.clock,
    required this.frames,
    required this.frameRate,
    required this.lapSeconds,
    required this.boyHeight,
    required this.boyWidth,
    required this.waterHeight,
    required this.waterColor,
    required this.deepWaterColor,
    required this.shineColor,
  }) : super(repaint: clock);

  // waterline in the source frames, as a fraction of frame height
  static const double bellyLine = 0.56;
  static const double _tilt = -0.40;
  static const double _rock = 0.05;

  // whole numbers so the water loops seamlessly when a lap restarts
  static const int ripplesPerLap = 6;
  static const int wakePerLap = 14;
  static const int _shimmersPerLap = 2;
  static const int _splashesPerLap = 15;

  final ValueNotifier<Duration> clock;
  final List<ui.Image> frames;
  final double frameRate;
  final double lapSeconds;
  final double boyHeight;
  final double boyWidth;
  final double waterHeight;
  final Color waterColor;
  final Color deepWaterColor;
  final Color shineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock.value.inMicroseconds / 1e6;
    final t = (seconds % lapSeconds) / lapSeconds;
    final waterTop = size.height - waterHeight;
    final left = -boyWidth + t * (size.width + boyWidth * 1.2);
    final boyCenterX = left + boyWidth * 0.5;

    canvas.clipRect(Offset.zero & size);

    if (frames.isNotEmpty) {
      final pos = (seconds * frameRate) % frames.length;
      final stroke = pos / frames.length * 2 * math.pi;
      final bob = math.sin(stroke) * 1.2;
      final angle = _tilt + math.sin(stroke + math.pi / 2) * _rock;
      final top = waterTop - 3 - boyHeight * bellyLine + bob;
      _paintBoy(
        canvas,
        pos,
        Rect.fromLTWH(left, top, boyWidth, boyHeight),
        angle,
      );
    }

    _paintWater(
      canvas,
      size,
      _Water(
        t: t,
        boyCenterX: boyCenterX,
        boyWidth: boyWidth,
        waterTop: waterTop,
      ),
    );
  }

  void _paintBoy(Canvas canvas, double pos, Rect dst, double angle) {
    final i = pos.floor() % frames.length;
    final next = (i + 1) % frames.length;
    final mix = pos - pos.floor();

    canvas.save();
    final pivot = Offset(dst.center.dx, dst.top + dst.height * bellyLine);
    canvas
      ..translate(pivot.dx, pivot.dy)
      ..rotate(angle)
      ..translate(-pivot.dx, -pivot.dy);

    final paint = Paint()..filterQuality = FilterQuality.medium;
    void draw(ui.Image img, double opacity, BlendMode mode) {
      paint
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..blendMode = mode;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        paint,
      );
    }

    // cross-fade added in a layer so overlapping opaque areas stay opaque
    canvas.saveLayer(dst.inflate(2), Paint());
    draw(frames[i], 1 - mix, BlendMode.srcOver);
    draw(frames[next], mix, BlendMode.plus);
    canvas
      ..restore()
      ..restore();
  }

  void _paintWater(Canvas canvas, Size size, _Water water) {
    final w = size.width;
    final waterTop = water.waterTop;

    final surface = <Offset>[
      for (double x = 0; x <= w + 2; x += 2)
        Offset(x, waterTop - water.lift(x)),
    ];
    final path = Path()..moveTo(0, size.height);
    for (final p in surface) {
      path.lineTo(p.dx, p.dy);
    }
    path
      ..lineTo(w, size.height)
      ..close();

    final bounds = Rect.fromLTRB(0, waterTop - 10, w, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            waterColor.withOpacity(0.85),
            deepWaterColor.withOpacity(0.95),
          ],
        ).createShader(bounds),
    );

    final sweep = (water.t * _shimmersPerLap) % 1.0;
    final band = -0.3 + sweep * 1.6;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            shineColor.withOpacity(0),
            shineColor.withOpacity(0.8),
            shineColor.withOpacity(0),
          ],
          stops: [
            (band - 0.12).clamp(0.0, 1.0),
            band.clamp(0.0, 1.0),
            (band + 0.12).clamp(0.0, 1.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height)),
    );

    _paintFoam(canvas, surface, waterTop);
    _paintSplashes(canvas, water);
  }

  void _paintFoam(Canvas canvas, List<Offset> surface, double waterTop) {
    final foam = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < surface.length; i++) {
      final a = surface[i - 1];
      final b = surface[i];
      final strength = ((waterTop - b.dy) / 6).clamp(0.0, 1.0);
      if (strength < 0.15) continue;
      foam.color = Colors.white.withOpacity(0.75 * strength);
      canvas.drawLine(a, b, foam);
    }
  }

  void _paintSplashes(Canvas canvas, _Water water) {
    final drop = Paint();
    final feetX = water.boyCenterX - boyWidth * 0.42;
    final handX = water.boyCenterX + boyWidth * 0.4;

    for (var i = 0; i < 6; i++) {
      final phase = (water.t * _splashesPerLap + i / 6) % 1.0;
      final arc = math.sin(phase * math.pi);
      final fromFeet = i.isEven;
      final originX = fromFeet ? feetX : handX;
      final dir = fromFeet ? -1.0 : 0.6;
      final spread = (i - 2.5) * 1.8;

      final pos = Offset(
        originX + dir * phase * 14 + spread,
        water.waterTop - 3 - arc * (fromFeet ? 9 : 6),
      );
      drop.color = Colors.white.withOpacity(0.9 * (1 - phase));
      canvas.drawCircle(pos, 1.6 * (1 - phase) + 0.4, drop);
    }
  }

  @override
  bool shouldRepaint(_SwimPainter oldDelegate) =>
      oldDelegate.frames != frames ||
      oldDelegate.frameRate != frameRate ||
      oldDelegate.lapSeconds != lapSeconds ||
      oldDelegate.boyHeight != boyHeight ||
      oldDelegate.waterHeight != waterHeight;
}

class _Water {
  _Water({
    required this.t,
    required this.boyCenterX,
    required this.boyWidth,
    required this.waterTop,
  }) : _phase = t * 2 * math.pi;

  final double t;
  final double boyCenterX;
  final double boyWidth;
  final double waterTop;
  final double _phase;

  double lift(double x) {
    final d = x - boyCenterX;
    var lift = math.sin(x / 10 + _phase * _SwimPainter.ripplesPerLap) * 0.5;

    final bodyEnv = math.exp(-math.pow(d / (boyWidth * 0.42), 2));
    lift += bodyEnv *
        (5 + 1.5 * math.sin(d / 7 - _phase * _SwimPainter.wakePerLap));

    final bowEnv = math.exp(-math.pow((d - boyWidth * 0.48) / 10, 2));
    lift += bowEnv * 2.5;

    if (d < 0) {
      final wakeEnv = math.exp(d / (boyWidth * 1.6));
      final crest =
          (math.sin(d / 9 + _phase * _SwimPainter.wakePerLap) + 1) / 2;
      lift += wakeEnv * crest * 4;
    }
    return lift;
  }
}
