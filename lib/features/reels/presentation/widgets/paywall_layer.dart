import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';

// stays mounted on the locked reel while it scrolls, so swiping away plays
// the leave instead of cutting the blur off mid-gesture; every visit plays
// the entrance again
class PaywallLayer extends StatelessWidget {
  const PaywallLayer({required this.episode, required this.focused, super.key});

  // catalogue index of the reel underneath
  final int episode;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    if (!PaywallState.policy.isLockedEpisode(episode)) {
      return const SizedBox.shrink();
    }
    final locked = context.select<PaywallBloc, bool>(
      (bloc) => bloc.state.showsOn(episode),
    );
    return Paywall(
      visible: focused && locked,
      onUnlock: () => context.read<PaywallBloc>().add(const PaywallUnlocked()),
    );
  }
}

class Paywall extends StatefulWidget {
  const Paywall({required this.visible, required this.onUnlock, super.key});

  final bool visible;
  final VoidCallback onUnlock;

  // the brief asks for a simulated unlock; this delay stands in for the
  // purchase round trip
  static const Duration unlockDelay = Duration(milliseconds: 600);

  @override
  State<Paywall> createState() => _PaywallState();
}

class _PaywallState extends State<Paywall> with TickerProviderStateMixin {
  static const double _maxBlur = 18;

  // low damping so the card overshoots and settles with a bounce
  static const SpringDescription _bounce =
      SpringDescription(mass: 1, stiffness: 170, damping: 15);

  // blur, scrim and the staggered card content run on this one
  late final AnimationController _reveal;

  // unbounded so the spring can run past 1 before settling
  late final AnimationController _card;

  late final CurvedAnimation _blur;
  late final CurvedAnimation _title;
  late final CurvedAnimation _body;
  late final CurvedAnimation _cta;

  bool _shown = false;
  bool _busy = false;
  Timer? _purchase;

  @override
  void initState() {
    super.initState();
    // created up front: a lazy one would first be built in dispose() on
    // every reel that never showed the paywall
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      reverseDuration: const Duration(milliseconds: 320),
    );
    _card = AnimationController.unbounded(vsync: this);
    _blur = _step(0, 0.5);
    _title = _step(0.25, 0.6);
    _body = _step(0.4, 0.75);
    _cta = _step(0.55, 0.9);
    if (widget.visible) _enter();
  }

  @override
  void didUpdateWidget(Paywall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    widget.visible ? _enter() : unawaited(_leave());
  }

  @override
  void dispose() {
    _purchase?.cancel();
    for (final step in [_blur, _title, _body, _cta]) {
      step.dispose();
    }
    _reveal.dispose();
    _card.dispose();
    super.dispose();
  }

  void _enter() {
    _shown = true;
    _busy = false;
    _card.value = 0;
    unawaited(_reveal.forward(from: 0));
    unawaited(_card.animateWith(SpringSimulation(_bounce, 0, 1, 0)));
  }

  Future<void> _leave() async {
    await Future.wait([
      _reveal.reverse().orCancel.catchError((Object _) {}),
      _card
          .animateTo(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInCubic,
          )
          .orCancel
          .catchError((Object _) {}),
    ]);
    if (mounted && !widget.visible) setState(() => _shown = false);
  }

  void _unlock() {
    if (_busy) return;
    setState(() => _busy = true);
    _purchase = Timer(Paywall.unlockDelay, widget.onUnlock);
  }

  CurvedAnimation _step(double begin, double end) => CurvedAnimation(
        parent: _reveal,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        // swallows taps meant for the reel underneath; vertical drags still
        // reach the feed, so going back works
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _blur,
              builder: (context, _) {
                final sigma = _maxBlur * _blur.value;
                return BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: ColoredBox(
                    color: Colors.black.withOpacity(0.35 * _blur.value),
                  ),
                );
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _card,
            builder: (context, child) => FractionalTranslation(
              translation: Offset(0, 1 - _card.value),
              child: child,
            ),
            child: SafeArea(
              top: false,
              child: _Card(
                title: _title,
                body: _body,
                cta: _cta,
                busy: _busy,
                onUnlock: _unlock,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.body,
    required this.cta,
    required this.busy,
    required this.onUnlock,
  });

  final Animation<double> title;
  final Animation<double> body;
  final Animation<double> cta;
  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: AppColors.inkRaised,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.inkLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Rise(
            animation: title,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: AppColors.limeToTeal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.lock_rounded, color: AppColors.ink),
                ),
                const SizedBox(width: 14),
                CustomText(
                  AppStrings.unlockTitle,
                  semanticLocator: 'paywall_title',
                  textStyle: AppTextStyles.heading,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Rise(
            animation: body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  AppStrings.unlockBody,
                  semanticLocator: 'paywall_body',
                  textStyle: AppTextStyles.muted,
                ),
                const SizedBox(height: 6),
                CustomText(
                  AppStrings.unlockPrice,
                  semanticLocator: 'paywall_price',
                  textStyle: AppTextStyles.heading.copyWith(
                    color: AppColors.lime,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _Rise(
            animation: cta,
            child: ShimmerButton(
              label: busy ? AppStrings.unlocking : AppStrings.unlockCta,
              onTap: busy ? null : onUnlock,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }
}

// a light sweep crosses the button once every 3s to pull the eye
class ShimmerButton extends StatefulWidget {
  const ShimmerButton({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  static const Duration period = Duration(seconds: 3);
  static const Duration sweep = Duration(milliseconds: 1200);

  @override
  State<ShimmerButton> createState() => _ShimmerButtonState();
}

class _ShimmerButtonState extends State<ShimmerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: ShimmerButton.sweep,
  );
  Timer? _rest;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // the pause is a plain timer rather than an idle stretch of the
    // animation, so no frames are drawn while nothing moves; the blur behind
    // the card is redrawn on every frame
    _sweep.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _rest = Timer(ShimmerButton.period - ShimmerButton.sweep, _run);
    });
    _run();
  }

  void _run() => unawaited(_sweep.forward(from: 0));

  @override
  void dispose() {
    _rest?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  void _press({required bool down}) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(26),
      ),
      child: CustomText(
        widget.label,
        semanticLocator: 'paywall_cta',
        textStyle: AppTextStyles.cta,
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      child: GestureDetector(
        onTapDown: (_) => _press(down: true),
        onTapUp: (_) => _press(down: false),
        onTapCancel: () => _press(down: false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 220),
          curve: _pressed ? Curves.easeOut : Curves.elasticOut,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _sweep,
              child: pill,
              builder: (context, child) {
                if (!_sweep.isAnimating) return child!;
                // the band starts and ends fully outside the button
                final at = -0.3 + _sweep.value * 1.6;
                return ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) => LinearGradient(
                    colors: const [
                      Color(0x00FFFFFF),
                      Color(0x99FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [
                      (at - 0.15).clamp(0.0, 1.0),
                      at.clamp(0.0, 1.0),
                      (at + 0.15).clamp(0.0, 1.0),
                    ],
                  ).createShader(rect),
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
