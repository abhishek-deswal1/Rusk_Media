import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rusk_media/core/ads/ad_preloader.dart';
import 'package:rusk_media/core/ads/ad_slot_state.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/theme/app_colors.dart';
import 'package:rusk_media/core/theme/app_text_styles.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/shared/widgets/connection_state/connection_state_view.dart';

// a full-screen ad between episodes. there is deliberately no gesture
// detector here: like, scrub and tap-to-pause belong to episodes only, the
// ad's own taps reach the native view and vertical drags reach the feed
class AdPage extends StatefulWidget {
  const AdPage({required this.page, required this.slotId, super.key});

  final int page;
  final String slotId;

  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> with AutomaticKeepAliveClientMixin {
  static const Duration _uncover = Duration(milliseconds: 320);

  // the loading screen still lies over a loaded ad, fading off it
  bool _covering = true;

  // the native view stays alive, so swiping back to it is instant too
  @override
  bool get wantKeepAlive => true;

  // runs at the end of the fade, possibly mid-build, so drop the cover on
  // the next frame
  void _uncovered() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _covering) setState(() => _covering = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final focused = context.select<ReelsBloc, bool>(
      (bloc) => bloc.state.focusedPage == widget.page,
    );
    return ColoredBox(
      color: AppColors.ink,
      child: ValueListenableBuilder<AdSlotState>(
        valueListenable: context.read<AdPreloader>().stateOf(widget.slotId),
        builder: (context, state, _) {
          final ad = state is AdSlotLoaded ? state.ad : null;
          // the ad goes in underneath and the loading screen fades off it.
          // the native ad view itself is never put under an opacity or a
          // transform: on android that is costly and can draw it wrong
          return Stack(
            alignment: Alignment.center,
            children: [
              if (ad != null)
                _LoadedAd(key: _LoadedAd.slot, ad: ad, animate: focused),
              // a failed slot is taken out of the feed, it never shows broken
              if (ad == null || _covering)
                IgnorePointer(
                  key: const ValueKey('cover'),
                  ignoring: ad != null,
                  child: AnimatedOpacity(
                    opacity: ad == null ? 1 : 0,
                    // an ad that lands while its page is still off screen
                    // shows at once, so it is already there on arrival
                    duration: focused ? _uncover : Duration.zero,
                    curve: Curves.easeOutCubic,
                    onEnd: ad == null ? null : _uncovered,
                    child: TickerMode(
                      // built next door and kept alive, so only animate on
                      // screen, and not at all once the ad is in
                      enabled: focused && ad == null,
                      child: const ConnectionStateView(
                        mode: ConnectionViewMode.loading,
                      ),
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

class _LoadedAd extends StatefulWidget {
  const _LoadedAd({required this.ad, required this.animate, super.key});

  static const Key slot = ValueKey('loaded');

  final NativeAd ad;
  final bool animate;

  @override
  State<_LoadedAd> createState() => _LoadedAdState();
}

// the chip drops in and the hint rises after it, when the ad lands on
// screen. one that was ready before its page came on screen is simply
// already in place, so nothing runs while the reel next door plays
class _LoadedAdState extends State<_LoadedAd>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final CurvedAnimation _chip;
  late final CurvedAnimation _hint;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _chip = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
    );
    _hint = CurvedAnimation(
      parent: _enter,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      unawaited(_enter.forward());
    } else {
      _enter.value = 1;
    }
  }

  @override
  void dispose() {
    _chip.dispose();
    _hint.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: widget.animate,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _Enter(
              animation: _chip,
              from: const Offset(0, -0.4),
              child: const _SponsoredChip(),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // the size range google gives for the medium template
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 320,
                  minHeight: 320,
                  maxWidth: 400,
                  maxHeight: 400,
                ),
                child: AdWidget(ad: widget.ad),
              ),
            ),
            const Spacer(),
            _Enter(
              animation: _hint,
              from: const Offset(0, 0.4),
              child: const _SwipeOnHint(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Enter extends StatelessWidget {
  const _Enter({
    required this.animation,
    required this.from,
    required this.child,
  });

  final Animation<double> animation;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: from, end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }
}

class _SponsoredChip extends StatelessWidget {
  const _SponsoredChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inkLine,
        borderRadius: BorderRadius.circular(20),
      ),
      child: CustomText(
        AppStrings.sponsored,
        semanticLocator: 'ad_sponsored',
        textStyle: AppTextStyles.count,
      ),
    );
  }
}

class _SwipeOnHint extends StatefulWidget {
  const _SwipeOnHint();

  @override
  State<_SwipeOnHint> createState() => _SwipeOnHintState();
}

class _SwipeOnHintState extends State<_SwipeOnHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_bob.repeat(reverse: true));
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _bob,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -6 * Curves.easeInOut.transform(_bob.value)),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              color: AppColors.textMuted,
            ),
            CustomText(
              AppStrings.adSwipeOn,
              semanticLocator: 'ad_swipe_on',
              textStyle: AppTextStyles.muted,
            ),
          ],
        ),
      ),
    );
  }
}
