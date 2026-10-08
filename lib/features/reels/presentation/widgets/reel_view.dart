import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/ui/components/network_image_widget.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/gesture_guide.dart';
import 'package:rusk_media/features/reels/presentation/widgets/hold_indicator.dart';
import 'package:rusk_media/features/reels/presentation/widgets/like_burst.dart';
import 'package:rusk_media/features/reels/presentation/widgets/paywall_layer.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_action_rail.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_info_panel.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_progress_bar.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_surface.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reels_top_bar.dart';
import 'package:rusk_media/features/reels/presentation/widgets/tips_sheet.dart';

enum _HoldAxis { volume, seek }

class ReelView extends StatefulWidget {
  const ReelView({
    required this.page,
    required this.slot,
    required this.reel,
    super.key,
  });

  // where it sits in the feed, ads included
  final int page;

  // its player's key: the catalogue index, which ads never shift
  final int slot;
  final Reel reel;

  @override
  State<ReelView> createState() => _ReelViewState();
}

class _ReelViewState extends State<ReelView> {
  static const int _burstCap = 3;
  static const double _deadZone = 14;
  static const double _volumeTravel = 220;
  static const int _volumeSteps = 50;

  // scrubbing and volume start with a short hold, then a slide, from
  // anywhere on the reel. this is how "drag across the screen" is done here,
  // on purpose: a bare sideways drag would fire on every slightly diagonal
  // swipe to the next reel and on stray touches, jumping the video by
  // accident. the hold makes the intent clear first; after it, the slide
  // scrubs like dragging the bar, and the bar expands and shows the time
  // just the same. the bar itself still drags directly, no hold needed
  static const Duration _holdAfter = Duration(milliseconds: 250);

  final List<(int, Offset)> _bursts = [];
  int _burstSeq = 0;
  Offset _lastDoubleTap = Offset.zero;

  _HoldAxis? _axis;
  Offset _holdOrigin = Offset.zero;
  double _volumeAtHold = 1;
  Duration _positionAtHold = Duration.zero;
  double? _lastVolume;

  // pointer moves arrive every frame; only the indicator listens, the page
  // and its video stay put
  final ValueNotifier<HoldReading?> _reading = ValueNotifier(null);

  // raw pointer count; the gesture guide waits for the screen to be left
  // alone
  final ValueNotifier<bool> _touching = ValueNotifier(false);
  int _pointers = 0;

  VideoPoolBloc get _pool => context.read<VideoPoolBloc>();

  @override
  void dispose() {
    _reading.dispose();
    _touching.dispose();
    super.dispose();
  }

  void _pointerDown(PointerDownEvent _) => _touching.value = ++_pointers > 0;

  void _pointerUp(PointerEvent _) {
    _pointers = math.max(0, _pointers - 1);
    _touching.value = _pointers > 0;
  }

  void _toggle() => _pool.add(const VideoPoolPlaybackToggled());

  void _doubleTap() {
    context.read<EngagementBloc>().add(ReelDoubleTapped(widget.reel.id));
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      if (_bursts.length == _burstCap) _bursts.removeAt(0);
      _bursts.add((_burstSeq++, _lastDoubleTap));
    });
  }

  void _holdStart(LongPressStartDetails d) {
    _axis = null;
    _holdOrigin = d.localPosition;
    _volumeAtHold = _pool.state.volume;
    _lastVolume = _volumeAtHold;
    _positionAtHold =
        _pool.state.controllers[widget.slot]?.value.position ?? Duration.zero;
  }

  void _holdMove(LongPressMoveUpdateDetails d) {
    final delta = d.localPosition - _holdOrigin;
    _axis ??= delta.distance < _deadZone
        ? null
        : (delta.dx.abs() > delta.dy.abs() ? _HoldAxis.seek : _HoldAxis.volume);

    switch (_axis) {
      case null:
        return;
      case _HoldAxis.volume:
        final raw = (_volumeAtHold - delta.dy / _volumeTravel).clamp(0, 1);
        final level = (raw * _volumeSteps).round() / _volumeSteps;
        if (level == _lastVolume) return;
        _lastVolume = level;
        _pool.add(VideoPoolVolumeChanged(level));
        _reading.value = VolumeReading(level);
      case _HoldAxis.seek:
        final player = _pool.state.controllers[widget.slot];
        final width = context.size?.width ?? 0;
        if (player == null || width == 0) return;
        final length = player.value.duration;
        final moved = _positionAtHold + length * (delta.dx / width);
        final to = moved < Duration.zero
            ? Duration.zero
            : (moved > length ? length : moved);
        _reading.value = SeekReading(to: to, length: length);
    }
  }

  void _holdEnd(LongPressEndDetails d) {
    final aim = _reading.value;
    if (_axis == _HoldAxis.seek && aim is SeekReading) {
      _pool.add(VideoPoolSeekRequested(page: widget.slot, position: aim.to));
      _axis = null;
      _reading.value = SeekLanded(to: aim.to, length: aim.length);
      return;
    }
    _holdCancel();
  }

  // the system can take the pointer mid-hold (shade, home gesture, a call);
  // the bar follows _reading, so it must not be left aiming at a seek
  void _holdCancel() {
    _axis = null;
    _reading.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final focused = context.select<ReelsBloc, bool>(
      (bloc) => bloc.state.focusedPage == widget.page,
    );
    final playable = context.select<PaywallBloc, bool>(
      (bloc) => bloc.state.canPlay(widget.slot),
    );
    final edges = MediaQuery.systemGestureInsetsOf(context);

    // a Listener only observes pointers and never joins the gesture arena,
    // so every existing tap, hold, scrub and swipe behaves exactly as before
    return Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // the hold has its own recognizer only because GestureDetector
          // can't shorten the long-press delay. the surface is the
          // detectors' child rather than a sibling under them, so a failed
          // reel's own retry tap still wins the arena
          RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              if (focused)
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(
                    duration: _holdAfter,
                    debugOwner: this,
                  ),
                  (hold) => hold
                    ..onLongPressStart = _holdStart
                    ..onLongPressMoveUpdate = _holdMove
                    ..onLongPressEnd = _holdEnd
                    ..onLongPressCancel = _holdCancel,
                ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focused ? _toggle : null,
              onDoubleTapDown: (d) => _lastDoubleTap = d.localPosition,
              onDoubleTap: focused ? _doubleTap : null,
              // a locked episode never gets a player, only its poster
              child: playable
                  ? ReelSurface(page: widget.slot)
                  : _Poster(url: widget.reel.posterUrl),
            ),
          ),
          const IgnorePointer(child: _BottomFade()),
          // focus-only layers keep their slot either way, so a focus change
          // never shifts the siblings below and re-inflates the overlay
          _WhenFocused(focused: focused, child: const _PausedBadge()),
          for (final (id, at) in _bursts)
            LikeBurst(
              key: ValueKey(id),
              at: at,
              onFinished: () =>
                  setState(() => _bursts.removeWhere((b) => b.$1 == id)),
            ),
          ValueListenableBuilder<HoldReading?>(
            valueListenable: _reading,
            builder: (context, reading, _) => reading == null
                ? const SizedBox.shrink()
                : HoldIndicator(reading: reading),
          ),
          SafeArea(
            child: Stack(
              children: [
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ReelsTopBar(),
                ),
                Positioned(
                  right: 10,
                  bottom: 48,
                  child: ReelActionRail(reel: widget.reel),
                ),
                Positioned(
                  left: 18,
                  right: 92,
                  bottom: 52,
                  child: ReelInfoPanel(reel: widget.reel),
                ),
                // the bar is dragged sideways, so keep it out of the system
                // back-gesture strips, which SafeArea doesn't account for
                Positioned(
                  left: math.max(18, edges.left + 8),
                  right: math.max(18, edges.right + 8),
                  bottom: 6,
                  child: ReelProgressBar(page: widget.slot, hold: _reading),
                ),
              ],
            ),
          ),
          _WhenFocused(
            focused: focused,
            child: GestureGuide(
              touching: _touching,
              demo: _reading,
              length: () =>
                  _pool.state.controllers[widget.slot]?.value.duration ??
                  Duration.zero,
            ),
          ),
          PaywallLayer(episode: widget.slot, focused: focused),
          _WhenFocused(
            focused: focused,
            child: BlocSelector<OnboardingBloc, OnboardingState, bool>(
              selector: (s) => s.tipsPending,
              builder: (context, visible) => visible
                  ? TipsSheet(
                      onDone: () => context
                          .read<OnboardingBloc>()
                          .add(const TipsClosed()),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhenFocused extends StatelessWidget {
  const _WhenFocused({required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      focused ? child : const SizedBox.shrink();
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ColoredBox(
      color: AppColors.ink,
      child: NetworkImageWidget(
        url: url,
        size: size.width,
        height: size.height,
        placeholderIcon: Icons.movie_rounded,
      ),
    );
  }
}

class _BottomFade extends StatelessWidget {
  const _BottomFade();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.35,
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x99000000)],
            ),
          ),
        ),
      ),
    );
  }
}

class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<VideoPoolBloc, VideoPoolState, bool>(
      selector: (pool) =>
          pool.userPaused && pool.controllers.containsKey(pool.activePage),
      builder: (context, paused) => IgnorePointer(
        child: Center(
          child: AnimatedScale(
            scale: paused ? 1 : 1.4,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: paused ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 44,
                  color: AppColors.lime,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
