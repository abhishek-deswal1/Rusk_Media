import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/ads/ad_config.dart';
import 'package:rusk_media/core/ads/ad_preloader.dart';
import 'package:rusk_media/core/base/base_multi_bloc_provider_widget.dart';
import 'package:rusk_media/core/di/app_di.dart';
import 'package:rusk_media/core/di/reels_di.dart';
import 'package:rusk_media/core/ui/components/network_image_widget.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/ad_page.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_view.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reels_scroll_physics.dart';
import 'package:rusk_media/shared/widgets/connection_state/connection_state_view.dart';

class ReelsScreen extends BaseMultiBlocProviderWidget<ReelsBloc> {
  const ReelsScreen({super.key});

  // tips, the paywall and an ad page each hold every video
  @visibleForTesting
  static bool holdsPlayback(
    ReelsState feed,
    PaywallState paywall,
    OnboardingState onboarding,
  ) {
    final episode = feed.focusedEpisode;
    return (onboarding.tipsPending && feed.reels.isNotEmpty) ||
        feed.onAd ||
        (episode != null && paywall.showsOn(episode));
  }

  // a slot dropped behind the viewer moves the page, not the reel
  @visibleForTesting
  static bool movedToAnotherReel(ReelsState before, ReelsState after) =>
      before.focusedPage != after.focusedPage &&
      before.focusedEpisode != after.focusedEpisode;

  // the physics stop at the same lock, so the two never disagree
  @visibleForTesting
  static bool canFocus(int page, int? lockedPage) =>
      lockedPage == null || page <= lockedPage;

  // players are keyed by catalogue index, so dropping an ad slot never
  // reloads a video. null while there is nothing to play yet
  @visibleForTesting
  static VideoPoolWindowChanged? poolWindow(
    ReelsState s,
    PaywallState paywall,
  ) {
    if (s.phase != ReelsPhase.ready || s.reels.isEmpty) return null;
    final at = _ReelsScreenState._episodeAt(s.items, s.focusedPage);
    if (at == null) return null;
    const live = _ReelsScreenState._liveEachSide;
    const warm = _ReelsScreenState._warmAhead;
    final slots = [
      for (var i = at - live; i <= at + live; i++)
        if (i >= 0 && i < s.reels.length && paywall.canPlay(i))
          VideoSlot(page: i, url: s.reels[i].streamUrl),
    ];
    final liveUrls = {for (final slot in slots) slot.url};
    // a locked episode is still fetched to disk, so unlocking plays at once;
    // nothing past it is reachable, so nothing past it is fetched
    final lastReachable =
        paywall.lockedIndex(s.reels.length) ?? at + live + warm;
    final prefetch = [
      for (var i = at + 1; i <= at + live + warm; i++)
        if (i < s.reels.length &&
            i <= lastReachable &&
            !liveUrls.contains(s.reels[i].streamUrl))
          s.reels[i].streamUrl,
    ];
    return VideoPoolWindowChanged(
      activePage: at,
      slots: slots,
      prefetchUrls: prefetch,
    );
  }

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

// the feed is the primary bloc; likes and follows, the paywall and the
// first-run help have their own. none of them knows the others, so anything
// that needs two of them is worked out here
class _ReelsScreenState
    extends BaseMultiBlocProviderWidgetState<ReelsScreen, ReelsBloc> {
  // live players: the focused reel and one either side; the two after that
  // are only fetched to disk. three decoders buy an instant swipe, the warm
  // fetch buys a quick start for bandwidth; both are read with DevTools on a
  // real device before either number moves
  static const int _liveEachSide = 1;
  static const int _warmAhead = 2;

  final VideoPoolBloc _pool = AppDI.videoPool;
  final AdPreloader _ads = ReelsDI.makeAdPreloader();
  late final StreamSubscription<String> _adFailures;
  late final EngagementBloc _engagement;
  late final PaywallBloc _paywall;
  late final OnboardingBloc _onboarding;
  bool _held = false;

  @override
  void onInitWidget() {
    _engagement = ReelsDI.makeEngagementBloc();
    _paywall = ReelsDI.makePaywallBloc();
    _onboarding = ReelsDI.makeOnboardingBloc();
  }

  @override
  ReelsBloc getPrimaryBlocInstance() =>
      ReelsDI.makeReelsBloc()..add(const ReelsOpened());

  @override
  List<BlocProvider> buildSecondaryProviders() => [
        BlocProvider<EngagementBloc>.value(value: _engagement),
        BlocProvider<PaywallBloc>.value(value: _paywall),
        BlocProvider<OnboardingBloc>.value(value: _onboarding),
      ];

  @override
  bool extendBodyBehindAppBar() => true;

  @override
  void initState() {
    super.initState();
    _adFailures =
        _ads.failures.listen((slotId) => bloc.add(AdSlotFailed(slotId)));
  }

  @override
  void dispose() {
    unawaited(_adFailures.cancel());
    unawaited(_engagement.close());
    unawaited(_paywall.close());
    unawaited(_onboarding.close());
    _ads.dispose();
    // the pool lives for the whole app; give back every player it holds
    _pool
      ..add(const VideoPoolWindowChanged(activePage: 0, slots: []))
      ..add(const VideoPoolHoldChanged(held: false));
    super.dispose();
  }

  // sent before the window moves, so stepping onto an ad never starts the
  // next episode just to pause it again
  void _syncHold() {
    final held = ReelsScreen.holdsPlayback(
      bloc.state,
      _paywall.state,
      _onboarding.state,
    );
    if (held == _held) return;
    _held = held;
    _pool.add(VideoPoolHoldChanged(held: held));
  }

  void _feedPool(ReelsState s) {
    final window = ReelsScreen.poolWindow(s, _paywall.state);
    if (window != null) _pool.add(window);
  }

  // the episode on screen; on an ad, the one after it, so the next swipe
  // starts at once while the one before the ad stays warm behind it
  static int? _episodeAt(List<FeedItem> items, int page) {
    for (var p = page; p < items.length; p++) {
      if (items[p] case EpisodeItem(:final index)) return index;
    }
    return null;
  }

  // the locked episode only ever shows its poster, behind the paywall blur;
  // decoded ahead at the size it is drawn so it is there the moment the
  // paywall opens. the other posters are never shown, so never fetched
  void _precacheLockedPoster(BuildContext context, ReelsState s) {
    final locked = _paywall.state.lockedIndex(s.reels.length);
    if (locked == null || locked >= s.reels.length) return;
    final url = s.reels[locked].posterUrl;
    if (url.isEmpty) return;
    unawaited(
      precacheImage(
        NetworkImageWidget.provider(
          url,
          width: MediaQuery.sizeOf(context).width,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        context,
        // a miss here only means the poster loads when shown
        onError: (_, __) {},
      ),
    );
  }

  void _preloadAds(ReelsState s) {
    if (s.phase != ReelsPhase.ready) return;
    _ads.load(
      ReelsState.composer.slotsToLoad(
        s.items,
        current: s.focusedPage,
        ahead: AdConfig.preloadAhead,
      ),
    );
  }

  @override
  Widget buildScreen(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [RepositoryProvider<AdPreloader>.value(value: _ads)],
      child: BlocProvider<VideoPoolBloc>.value(
        value: _pool,
        child: MultiBlocListener(
          listeners: [
            BlocListener<ReelsBloc, ReelsState>(
              listener: (_, __) => _syncHold(),
            ),
            BlocListener<ReelsBloc, ReelsState>(
              listenWhen: (a, b) =>
                  a.phase != b.phase ||
                  a.focusedPage != b.focusedPage ||
                  a.reels != b.reels ||
                  a.removedSlots != b.removedSlots,
              listener: (_, s) {
                _feedPool(s);
                _preloadAds(s);
              },
            ),
            BlocListener<ReelsBloc, ReelsState>(
              listenWhen: (a, b) => a.removedSlots != b.removedSlots,
              listener: (_, s) => s.removedSlots.forEach(_ads.release),
            ),
            BlocListener<ReelsBloc, ReelsState>(
              listenWhen: (a, b) =>
                  _paywall.state.lockedIndex(a.reels.length) !=
                  _paywall.state.lockedIndex(b.reels.length),
              listener: _precacheLockedPoster,
            ),
            BlocListener<PaywallBloc, PaywallState>(
              listener: (_, __) {
                _syncHold();
                _feedPool(bloc.state);
              },
            ),
            BlocListener<OnboardingBloc, OnboardingState>(
              listener: (_, __) => _syncHold(),
            ),
            BlocListener<ReelsBloc, ReelsState>(
              listenWhen: ReelsScreen.movedToAnotherReel,
              listener: (_, __) => _onboarding.add(const ReelMovedOn()),
            ),
          ],
          child: const _Body(),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReelsBloc, ReelsState>(
      buildWhen: (a, b) =>
          a.phase != b.phase ||
          a.reloading != b.reloading ||
          a.reels.isEmpty != b.reels.isEmpty,
      builder: (context, s) {
        void reload() =>
            context.read<ReelsBloc>().add(const ReelsReloadRequested());

        return switch (s.phase) {
          ReelsPhase.idle ||
          ReelsPhase.fetching =>
            const ConnectionStateView(mode: ConnectionViewMode.loading),
          // a retry tap shows the loading tv until the check answers
          _ when s.reloading =>
            const ConnectionStateView(mode: ConnectionViewMode.loading),
          ReelsPhase.offline => ConnectionStateView(
              mode: ConnectionViewMode.offline,
              isRetrying: s.reloading,
              onRetry: reload,
            ),
          ReelsPhase.broken => ConnectionStateView(
              mode: ConnectionViewMode.error,
              isRetrying: s.reloading,
              onRetry: reload,
            ),
          ReelsPhase.ready when s.reels.isEmpty => ConnectionStateView(
              mode: ConnectionViewMode.empty,
              isRetrying: s.reloading,
              onRetry: reload,
            ),
          ReelsPhase.ready => const Stack(
              fit: StackFit.expand,
              children: [_Pager(), _FirstFrameCover()],
            ),
        };
      },
    );
  }
}

class _Pager extends StatefulWidget {
  const _Pager();

  @override
  State<_Pager> createState() => _PagerState();
}

class _PagerState extends State<_Pager> {
  late final ReelsBloc _reels = context.read<ReelsBloc>();
  late final PaywallBloc _paywall = context.read<PaywallBloc>();
  late final PageController _pages =
      PageController(initialPage: _reels.state.focusedPage);
  late final ValueNotifier<int?> _lock = ValueNotifier(_lockedPage());

  int? _lockedPage() => _paywall.state.lockedPage(_reels.state.items);

  @override
  void dispose() {
    _lock.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _move(PageMove move) {
    if (!_pages.hasClients) {
      _reels.add(const FeedScrollChanged(scrolling: false));
      return;
    }
    if (move.animate) {
      unawaited(
        _pages.animateToPage(
          move.page,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _pages.jumpToPage(move.page);
    }
  }

  bool _onScroll(ScrollNotification n) {
    // only the feed itself, not anything scrolling inside a page
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _reels.add(const FeedScrollChanged(scrolling: true));
    } else if (n is ScrollEndNotification) {
      _reels.add(const FeedScrollChanged(scrolling: false));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ReelsBloc, ReelsState>(
          listenWhen: (a, b) =>
              a.reels != b.reels || a.removedSlots != b.removedSlots,
          listener: (_, __) => _lock.value = _lockedPage(),
        ),
        BlocListener<PaywallBloc, PaywallState>(
          listener: (_, __) => _lock.value = _lockedPage(),
        ),
        BlocListener<ReelsBloc, ReelsState>(
          listenWhen: (a, b) => a.pageMove != b.pageMove && b.pageMove != null,
          listener: (_, s) => _move(s.pageMove!),
        ),
      ],
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: BlocBuilder<ReelsBloc, ReelsState>(
          buildWhen: (a, b) =>
              a.reels != b.reels || a.removedSlots != b.removedSlots,
          builder: (context, s) {
            final items = s.items;
            return PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              // the physics snap to pages themselves; PageView's own snapping
              // would wrap them and the lock's fling handling would never run
              pageSnapping: false,
              physics: PaywallLockPhysics(lockedPage: _lock),
              // keeps one neighbour built, so a swipe reveals a ready frame
              allowImplicitScrolling: true,
              itemCount: items.length,
              // pages keep their state when a dropped slot shifts the indices
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final page = items.indexWhere((e) => e.key == key.value);
                return page == -1 ? null : page;
              },
              onPageChanged: (page) {
                if (!ReelsScreen.canFocus(page, _lock.value)) return;
                _reels.add(ReelFocused(page));
              },
              itemBuilder: (context, page) => switch (items[page]) {
                final EpisodeItem item => ReelView(
                    key: ValueKey(item.key),
                    page: page,
                    slot: item.index,
                    reel: item.reel,
                  ),
                final AdSlotItem item => AdPage(
                    key: ValueKey(item.key),
                    page: page,
                    slotId: item.slotId,
                  ),
              },
            );
          },
        ),
      ),
    );
  }
}

// the loading screen stays until the first reel can actually play, unless
// that reel failed, in which case its own retry takes over
class _FirstFrameCover extends StatelessWidget {
  const _FirstFrameCover();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<VideoPoolBloc, VideoPoolState, bool>(
      selector: (pool) =>
          !pool.hasStarted && !pool.failed.contains(pool.activePage),
      builder: (context, covering) => IgnorePointer(
        ignoring: !covering,
        child: AnimatedOpacity(
          opacity: covering ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          child: covering
              ? const ConnectionStateView(mode: ConnectionViewMode.loading)
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
