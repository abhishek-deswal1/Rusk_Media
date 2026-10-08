import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/hold_indicator.dart';
import 'package:rusk_media/shared/widgets/connection_state/swimming_loader.dart';
import 'package:video_player/video_player.dart';

class ReelProgressBar extends StatelessWidget {
  const ReelProgressBar({required this.page, required this.hold, super.key});

  final int page;

  // a hold-and-slide seek anywhere on the reel; the bar follows it
  final ValueListenable<HoldReading?> hold;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<VideoPoolBloc, VideoPoolState, VideoPlayerController?>(
      selector: (pool) => pool.controllers[page],
      builder: (context, player) {
        if (player == null) return const SizedBox(height: 32);
        return _BufferSwap(
          player: player,
          hold: hold,
          track: _Track(
            player: player,
            hold: hold,
            onJump: (to) => context
                .read<VideoPoolBloc>()
                .add(VideoPoolSeekRequested(page: page, position: to)),
          ),
        );
      },
    );
  }
}

// share of the video a hold-and-slide seek is aiming at
double? _seekShare(HoldReading? reading) => switch (reading) {
      SeekReading(:final to, :final length) when length > Duration.zero =>
        (to.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0),
      _ => null,
    };

// while a playing reel stalls, the swimmer takes the bar's place. short
// hiccups are ignored so it doesn't flicker, and it's only mounted while
// stalled, so a playing reel pays nothing for it. the bar itself stays
// mounted (just invisible) so a scrub in progress survives and the viewer
// can still seek out of a bad stall
class _BufferSwap extends StatefulWidget {
  const _BufferSwap({
    required this.player,
    required this.hold,
    required this.track,
  });

  final VideoPlayerController player;
  final ValueListenable<HoldReading?> hold;
  final Widget track;

  static const Duration showAfter = Duration(milliseconds: 300);

  @override
  State<_BufferSwap> createState() => _BufferSwapState();
}

class _BufferSwapState extends State<_BufferSwap> {
  Timer? _pending;
  bool _showing = false;
  int _fingersOnBar = 0;

  void _countFinger(int delta) {
    final before = _fingersOnBar > 0;
    _fingersOnBar = (_fingersOnBar + delta).clamp(0, 10);
    if ((_fingersOnBar > 0) != before) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(_BufferSwap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player == widget.player) return;
    oldWidget.player.removeListener(_sync);
    widget.player.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _pending?.cancel();
    widget.player.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final v = widget.player.value;
    if (v.isBuffering && v.isPlaying) {
      if (_showing || _pending != null) return;
      _pending = Timer(_BufferSwap.showAfter, () {
        _pending = null;
        if (mounted) setState(() => _showing = true);
      });
    } else {
      _pending?.cancel();
      _pending = null;
      if (_showing) setState(() => _showing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _countFinger(1),
      onPointerUp: (_) => _countFinger(-1),
      onPointerCancel: (_) => _countFinger(-1),
      child: ValueListenableBuilder<HoldReading?>(
        valueListenable: widget.hold,
        child: widget.track,
        builder: (context, reading, track) {
          // a finger on the bar, or a seek from anywhere on the reel, always
          // gets the real bar back
          final seeking = _seekShare(reading) != null;
          final swimming = _showing && _fingersOnBar == 0 && !seeking;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(opacity: swimming ? 0 : 1, child: track),
              if (swimming)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(child: SwimmingLoader()),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Track extends StatefulWidget {
  const _Track({
    required this.player,
    required this.hold,
    required this.onJump,
  });

  final VideoPlayerController player;
  final ValueListenable<HoldReading?> hold;
  final ValueChanged<Duration> onJump;

  @override
  State<_Track> createState() => _TrackState();
}

class _TrackState extends State<_Track> {
  static const Duration _settleFor = Duration(seconds: 1);

  // within this of the target, the player has caught up
  static const int _caughtUpMs = 300;

  // set only while a finger is on the bar
  double? _held;

  // a seek that was just let go: the player still reports the old position
  // until its seek completes, so the bar stays on the target in the meantime
  // instead of snapping back for a frame or two
  double? _landing;
  Timer? _settle;

  Duration get _length => widget.player.value.duration;

  @override
  void initState() {
    super.initState();
    widget.hold.addListener(_onHold);
  }

  @override
  void didUpdateWidget(_Track oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayer);
      _landing = null;
      _settle?.cancel();
    }
    if (oldWidget.hold == widget.hold) return;
    oldWidget.hold.removeListener(_onHold);
    widget.hold.addListener(_onHold);
  }

  @override
  void dispose() {
    _settle?.cancel();
    widget.player.removeListener(_onPlayer);
    widget.hold.removeListener(_onHold);
    super.dispose();
  }

  void _onHold() {
    if (widget.hold.value case SeekLanded(:final to, :final length)
        when length > Duration.zero) {
      _land(to.inMilliseconds / length.inMilliseconds);
    }
  }

  void _land(double share) {
    _settle?.cancel();
    setState(() => _landing = share.clamp(0.0, 1.0));
    widget.player
      ..removeListener(_onPlayer)
      ..addListener(_onPlayer);
    _settle = Timer(_settleFor, _landed);
  }

  // one way: once the player has reached the target the bar follows it
  // again, so a reel that plays on past the target never snaps back to it
  void _onPlayer() {
    final at = _landing;
    if (at == null) return;
    final v = widget.player.value;
    final total = v.duration.inMilliseconds;
    final off = (v.position.inMilliseconds - at * total).abs();
    if (total == 0 || off <= _caughtUpMs) _landed();
  }

  void _landed() {
    _settle?.cancel();
    widget.player.removeListener(_onPlayer);
    if (mounted && _landing != null) setState(() => _landing = null);
  }

  void _hold(double x, double width) {
    if (width <= 0) return;
    setState(() => _held = (x / width).clamp(0.0, 1.0));
  }

  void _release() {
    final at = _held;
    if (at == null) return;
    widget.onJump(_length * at);
    _land(at);
    setState(() => _held = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _hold(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _hold(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: () => setState(() => _held = null),
          onTapUp: (d) {
            _hold(d.localPosition.dx, width);
            _release();
          },
          child: SizedBox(
            height: 32,
            child: ValueListenableBuilder<HoldReading?>(
              valueListenable: widget.hold,
              builder: (context, reading, _) => _Line(
                player: widget.player,
                held: _held ?? _seekShare(reading),
                landing: _landing,
                length: _length,
              ),
            ),
          ),
        );
      },
    );
  }
}

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

class _Line extends StatelessWidget {
  const _Line({
    required this.player,
    required this.held,
    required this.landing,
    required this.length,
  });

  final VideoPlayerController player;

  // where the viewer is aiming, while they hold the bar or seek elsewhere
  final double? held;
  final double? landing;
  final Duration length;

  static const double _readoutWidth = 104;

  @override
  Widget build(BuildContext context) {
    final at = held;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // the time preview sits on the bar, centred over the aimed point,
            // the same for a drag on the bar and a hold-and-slide anywhere,
            // the way video players usually show it. it is deliberately not
            // pinned under the fingertip: the finger would cover it, and in
            // a hold-and-slide the finger is nowhere near the bar
            if (at != null)
              Positioned(
                bottom: 26,
                left: (width * at - _readoutWidth / 2)
                    .clamp(0, width - _readoutWidth),
                child: Container(
                  width: _readoutWidth,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.inkRaised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: CustomText(
                    '${_clock(length * at)} / ${_clock(length)}',
                    semanticLocator: 'progress_readout',
                    textStyle: AppTextStyles.count,
                  ),
                ),
              ),
            // keyed: the readout above comes and goes, and without a key
            // this slot would be rebuilt from scratch each time, so the
            // bar would jump instead of springing
            Positioned.fill(
              key: const ValueKey('bar'),
              child: _SpringThickness(
                target: at != null ? 5 : 2.5,
                builder: (context, thickness) => RepaintBoundary(
                  child: CustomPaint(
                    painter: _BarPainter(
                      player: player,
                      held: at,
                      landing: landing,
                      thickness: thickness,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// the bar swells on a spring when grabbed and settles back when let go; it
// only runs when the target changes, never while the video plays
class _SpringThickness extends StatefulWidget {
  const _SpringThickness({required this.target, required this.builder});

  final double target;
  final Widget Function(BuildContext context, double thickness) builder;

  @override
  State<_SpringThickness> createState() => _SpringThicknessState();
}

class _SpringThicknessState extends State<_SpringThickness>
    with SingleTickerProviderStateMixin {
  // underdamped: a little past the target, then back
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 500, damping: 22);

  // a hundredth of a pixel is settled; no need to wait for a thousandth
  static const Tolerance _settled = Tolerance(distance: 0.01, velocity: 0.1);

  late final AnimationController _value = AnimationController.unbounded(
    vsync: this,
    value: widget.target,
  );

  @override
  void didUpdateWidget(_SpringThickness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) return;
    final target = widget.target;
    final run = _value.animateWith(
      SpringSimulation(
        _spring,
        _value.value,
        target,
        _value.velocity,
        tolerance: _settled,
      ),
    );
    // land exactly on the target, not just within the spring's tolerance
    unawaited(
      run.then((_) {
        if (mounted) _value.value = target;
      }),
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _value,
      builder: (context, _) =>
          widget.builder(context, math.max(1, _value.value).toDouble()),
    );
  }
}

// repaints straight from the player while it plays, so position ticks never
// rebuild a widget
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.player,
    required this.held,
    required this.landing,
    required this.thickness,
  }) : super(repaint: held == null ? player : null);

  final VideoPlayerController player;
  final double? held;
  final double? landing;
  final double thickness;

  static const double _thumb = 8;

  double get _share {
    final at = held ?? landing;
    if (at != null) return at;
    final v = player.value;
    final total = v.duration.inMilliseconds;
    if (total == 0) return 0;
    return (v.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final radius = Radius.circular(thickness);
    final filled = size.width * _share;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - thickness / 2, size.width, thickness),
          radius,
        ),
        Paint()..color = Colors.white24,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - thickness / 2, filled, thickness),
          radius,
        ),
        Paint()..color = AppColors.lime,
      );

    if (held == null) return;
    final thumb = Offset(filled.clamp(_thumb, size.width - _thumb), y);
    canvas
      ..drawCircle(thumb, _thumb, Paint()..color = AppColors.lime)
      ..drawCircle(
        thumb,
        _thumb - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.ink,
      );
  }

  @override
  bool shouldRepaint(_BarPainter oldDelegate) =>
      oldDelegate.player != player ||
      oldDelegate.held != held ||
      oldDelegate.landing != landing ||
      oldDelegate.thickness != thickness;
}
