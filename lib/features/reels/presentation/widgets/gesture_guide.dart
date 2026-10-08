import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/constants/app_images.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/ui/components/local_image_widget.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/hold_indicator.dart';

enum GuideStep { volume, timeline, swipe }

// first-run walkthrough, once the tips are closed: a hand acts out each
// gesture in turn. the volume and timeline steps also move the real meter
// and bar through [demo], for show only; nothing is seeked and the volume
// never changes. each step loops for a few seconds, a touch skips it, and
// moving to another reel ends the walk, since that was the last lesson
class GestureGuide extends StatefulWidget {
  const GestureGuide({
    required this.touching,
    required this.demo,
    required this.length,
    super.key,
  });

  // true while any finger is on the reel
  final ValueListenable<bool> touching;

  // the reel's hold reading, which the meter and the bar already follow
  final ValueNotifier<HoldReading?> demo;
  final ValueGetter<Duration> length;

  static const Duration idleBeforeShow = Duration(milliseconds: 500);
  static const Duration stepFor = Duration(seconds: 3);

  @override
  State<GestureGuide> createState() => _GestureGuideState();
}

class _GestureGuideState extends State<GestureGuide>
    with SingleTickerProviderStateMixin {
  static const double _width = 150;
  static const double _height = _width * 1024 / 1536;

  // where the fingertip sits inside the hand image
  static const Offset _tip = Offset(_width * 0.28, _height * 0.13);

  static const int _loops = 2;

  // share of each loop spent pressing before the slide
  static const double _press = 0.2;
  static const double _volumeTravel = 110;
  static const double _timelineTravel = 130;
  static const double _swipeTravel = 140;

  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: GestureGuide.stepFor,
  );

  Timer? _idle;
  bool _armed = false;
  int _step = 0;
  bool _demoing = false;

  GuideStep? get _current =>
      _step < GuideStep.values.length ? GuideStep.values[_step] : null;

  double get _phase => (_run.value * _loops) % 1;

  // the pool is held while tips, the paywall or an ad are up, so the hand
  // never plays over any of them
  bool get _shouldGuide =>
      context.read<OnboardingBloc>().state.swipeHintArmed &&
      !context.read<VideoPoolBloc>().state.held;

  void _syncArmed() {
    final armed = _shouldGuide;
    if (armed != _armed) _onArmed(armed);
  }

  @override
  void initState() {
    super.initState();
    _run
      ..addListener(_drive)
      ..addStatusListener(_onRun);
    widget.touching.addListener(_onTouch);
    _armed = _shouldGuide;
    _waitForIdle();
  }

  @override
  void didUpdateWidget(GestureGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.touching == widget.touching) return;
    oldWidget.touching.removeListener(_onTouch);
    widget.touching.addListener(_onTouch);
  }

  @override
  void dispose() {
    _idle?.cancel();
    widget.touching.removeListener(_onTouch);
    _clearDemo();
    _run.dispose();
    super.dispose();
  }

  void _onArmed(bool armed) {
    _armed = armed;
    if (armed) {
      _waitForIdle();
    } else {
      _stop(advance: false);
    }
  }

  // a touch skips the step on screen; the next one waits for the finger to
  // lift and the reel to be left alone again
  void _onTouch() {
    if (widget.touching.value) {
      _idle?.cancel();
      if (_run.isAnimating) _stop(advance: true);
    } else {
      _waitForIdle();
    }
  }

  void _waitForIdle() {
    _idle?.cancel();
    if (!_armed || widget.touching.value || _current == null) return;
    _idle = Timer(GestureGuide.idleBeforeShow, () {
      if (!mounted || !_armed || widget.touching.value || _current == null) {
        return;
      }
      unawaited(_run.forward(from: 0));
    });
  }

  void _onRun(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _stop(advance: true);
    _waitForIdle();
  }

  void _stop({required bool advance}) {
    _idle?.cancel();
    if (_run.isAnimating || _run.value > 0) _run.value = 0;
    _clearDemo();
    if (!advance) return;
    _step++;
    if (_current == null) {
      context.read<OnboardingBloc>().add(const SwipeHintPlayed());
    }
  }

  // 0 while pressing, then out to 1 and back over the rest of the loop
  static double _travel(double phase) {
    if (phase < _press) return 0;
    final p = (phase - _press) / (1 - _press);
    final there = p < 0.5 ? p * 2 : (1 - p) * 2;
    return Curves.easeInOutCubic.transform(there.clamp(0.0, 1.0));
  }

  void _drive() {
    if (!_run.isAnimating) return;
    final t = _travel(_phase);
    switch (_current) {
      case GuideStep.volume:
        _show(VolumeReading(0.25 + 0.6 * t));
      case GuideStep.timeline:
        final length = widget.length();
        if (length <= Duration.zero) return;
        _show(SeekReading(to: length * (0.2 + 0.6 * t), length: length));
      case GuideStep.swipe || null:
        return;
    }
  }

  void _show(HoldReading reading) {
    _demoing = true;
    widget.demo.value = reading;
  }

  void _clearDemo() {
    if (!_demoing) return;
    _demoing = false;
    widget.demo.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<OnboardingBloc, OnboardingState>(
          listenWhen: (a, b) => a.swipeHintArmed != b.swipeHintArmed,
          listener: (_, __) => _syncArmed(),
        ),
        BlocListener<VideoPoolBloc, VideoPoolState>(
          listenWhen: (a, b) => a.held != b.held,
          listener: (_, __) => _syncArmed(),
        ),
      ],
      child: IgnorePointer(
        // the thumb zone, lower right, clear of the system gesture strip;
        // its own layer, so the hand moving never repaints the reel
        child: SafeArea(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _run,
              builder: (context, hand) {
                final step = _current;
                if (!_run.isAnimating || step == null) {
                  return const SizedBox.shrink();
                }
                final phase = _phase;
                final t = _travel(phase);
                final v = _run.value;
                var opacity = math.min(1, math.min(v, 1 - v) / 0.06).toDouble();

                final Alignment at;
                final Offset move;
                switch (step) {
                  // beside the meter on the right edge, sliding up and down
                  case GuideStep.volume:
                    at = const Alignment(0.6, 0.3);
                    move = Offset(0, -t * _volumeTravel);
                  // just above the bar, sliding back and forth along it
                  case GuideStep.timeline:
                    at = const Alignment(0.35, 0.72);
                    move = Offset((t - 0.5) * _timelineTravel, 0);
                  // a swipe up per loop, fading in and out each time
                  case GuideStep.swipe:
                    at = const Alignment(0.45, 0.45);
                    final rise = Curves.easeInOutCubic.transform(
                      ((phase - 0.1) / 0.7).clamp(0.0, 1.0),
                    );
                    move = Offset(0, _swipeTravel / 2 - rise * _swipeTravel);
                    final stroke = math.min(phase / 0.15, (1 - phase) / 0.2);
                    opacity = math.min(opacity, stroke.clamp(0.0, 1.0));
                }

                final pressing = step != GuideStep.swipe && phase < _press;
                return Align(
                  alignment: at,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: move,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          hand!,
                          if (pressing) _HoldRing(progress: phase / _press),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const LocalImageWidget(
                asset: AppPngImages.guidingHand,
                width: _width,
                height: _height,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// grows out of the fingertip while the hand presses, to read as "hold"
class _HoldRing extends StatelessWidget {
  const _HoldRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final radius = 10 + 18 * progress;
    return Positioned(
      left: _GestureGuideState._tip.dx - radius,
      top: _GestureGuideState._tip.dy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.lime.withOpacity(1 - progress),
            width: 3,
          ),
        ),
      ),
    );
  }
}
