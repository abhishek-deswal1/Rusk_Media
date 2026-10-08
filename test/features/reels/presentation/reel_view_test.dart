import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/ui/components/network_image_widget.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/paywall_layer.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_surface.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_view.dart';

import '../../../helpers/fake_video_controller.dart';

class _MockReelsBloc extends MockBloc<ReelsEvent, ReelsState>
    implements ReelsBloc {}

class _MockPaywallBloc extends MockBloc<PaywallEvent, PaywallState>
    implements PaywallBloc {}

class _MockOnboardingBloc extends MockBloc<OnboardingEvent, OnboardingState>
    implements OnboardingBloc {}

// a returning viewer: no tips, no gesture guide
BlocProvider<OnboardingBloc> _returningViewer() {
  final onboarding = _MockOnboardingBloc();
  when(() => onboarding.state).thenReturn(const OnboardingState());
  return BlocProvider<OnboardingBloc>.value(value: onboarding);
}

void main() {
  const reel = Reel(
    id: 'a',
    handle: 'rusk',
    caption: 'hi',
    streamUrl: 'u0',
    avatarUrl: '',
  );

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('hold and slide sideways anywhere seeks through the bottom bar',
      (tester) async {
    final factory = FakeControllerFactory();
    final pool = VideoPoolBloc(
      controllerFactory: factory,
      afterFrame: () async {},
      setScreenAwake: ({required enable}) async {},
    );
    final reels = _MockReelsBloc();
    when(() => reels.state).thenReturn(
      const ReelsState(
        phase: ReelsPhase.ready,
        reels: [reel],
        canLoadMore: false,
      ),
    );
    pool.add(
      const VideoPoolWindowChanged(
        activePage: 0,
        slots: [VideoSlot(page: 0, url: 'u0')],
      ),
    );
    await tester.pump();
    final player = factory.complete(0);
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ReelsBloc>.value(value: reels),
            BlocProvider<VideoPoolBloc>.value(value: pool),
            BlocProvider<EngagementBloc>(create: (_) => EngagementBloc()),
            BlocProvider<PaywallBloc>(create: (_) => PaywallBloc()),
            _returningViewer(),
          ],
          child: const ReelView(page: 0, slot: 0, reel: reel),
        ),
      ),
    );
    tester.takeException();
    final readout = find.byWidgetPredicate(
      (w) => w is CustomText && w.semanticLocator == 'progress_readout',
    );
    expect(readout, findsNothing);

    // a press shorter than the hold is not one: sliding just moves on
    final quick = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 200));
    await quick.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(readout, findsNothing);
    await quick.up();
    await tester.pump(const Duration(milliseconds: 400));

    // the middle of the screen, nowhere near the bar; a quarter second is
    // enough of a hold, well under the platform's usual long press
    final hold = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 300));
    // a tenth of the width on, from 00:00 of a 30s reel
    await hold.moveBy(const Offset(40, 0));
    await hold.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<CustomText>(readout).text, '00:03 / 00:30');
    // the time lives on the bar only, not in a chip over the video
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);

    await hold.up();
    await tester.pump();
    expect(player.lastSeek, const Duration(seconds: 3));
    expect(readout, findsNothing);

    // the system taking the pointer mid-seek drops it without seeking and
    // leaves the bar back on playback
    player.lastSeek = null;
    final taken = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 300));
    await taken.moveBy(const Offset(40, 0));
    await taken.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(readout, findsOneWidget);

    await taken.cancel();
    await tester.pump(const Duration(milliseconds: 200));
    expect(readout, findsNothing);
    expect(player.lastSeek, isNull);

    await tester.pumpWidget(const SizedBox());
    unawaited(pool.close());
    await tester.pump();
  });

  testWidgets('a reel that failed to load retries when tapped', (tester) async {
    final factory = FakeControllerFactory();
    final pool = VideoPoolBloc(
      controllerFactory: factory,
      afterFrame: () async {},
      setScreenAwake: ({required enable}) async {},
    );
    final reels = _MockReelsBloc();
    // page 2 of a wrapping feed, so a retry wired to the wrong page shows up
    when(() => reels.state).thenReturn(
      const ReelsState(
        phase: ReelsPhase.ready,
        reels: [reel],
        canLoadMore: false,
        focusedPage: 2,
      ),
    );

    pool.add(
      const VideoPoolWindowChanged(
        activePage: 2,
        slots: [
          VideoSlot(page: 1, url: 'u1'),
          VideoSlot(page: 2, url: 'u0'),
        ],
      ),
    );
    await tester.pump();
    factory.fail(0);
    await tester.pump();
    expect(pool.state.failed, {2});

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ReelsBloc>.value(value: reels),
            BlocProvider<VideoPoolBloc>.value(value: pool),
            BlocProvider<EngagementBloc>(create: (_) => EngagementBloc()),
            BlocProvider<PaywallBloc>(create: (_) => PaywallBloc()),
            _returningViewer(),
          ],
          child: const ReelView(page: 2, slot: 2, reel: reel),
        ),
      ),
    );
    // fonts can't load in tests; not what this checks
    tester.takeException();

    await tester.tap(find.text(AppStrings.reelRetry));
    // the page's double-tap recognizer holds the arena until it times out
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();

    // focused page loads first, then its neighbour, then the retry
    expect(factory.requestedUrls, ['u0', 'u1', 'u0']);
    expect(pool.state.loading, {1, 2});
    expect(pool.state.userPaused, isFalse);

    // close runs on the fake clock, let the tester drive it
    unawaited(pool.close());
    await tester.pump();
  });

  testWidgets('the locked episode shows only its poster, never a player',
      (tester) async {
    final pool = VideoPoolBloc(
      controllerFactory: FakeControllerFactory(),
      afterFrame: () async {},
      setScreenAwake: ({required enable}) async {},
    );
    final reels = _MockReelsBloc();
    final episodes = [
      for (var i = 1; i <= 8; i++)
        Reel(
          id: 'e$i',
          handle: 'rusk',
          caption: 'Episode $i',
          streamUrl: 'u$i',
          avatarUrl: '',
          posterUrl: 'https://x/e$i.jpg',
        ),
    ];
    // E1 E2 E3 AD E4 E5 E6 AD E7 E8: episode 7 sits on page 8
    final locked = ReelsState(
      phase: ReelsPhase.ready,
      reels: episodes,
      canLoadMore: false,
      focusedPage: 8,
    );
    when(() => reels.state).thenReturn(locked);
    final paywall = _MockPaywallBloc();
    when(() => paywall.state).thenReturn(const PaywallState());
    final poster = find.byWidgetPredicate(
      (w) => w is NetworkImageWidget && w.url == 'https://x/e7.jpg',
    );

    Future<void> pumpEpisode(int slot) async {
      final page =
          locked.items.indexWhere((e) => e is EpisodeItem && e.index == slot);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ReelsBloc>.value(value: reels),
              BlocProvider<VideoPoolBloc>.value(value: pool),
              BlocProvider<EngagementBloc>(create: (_) => EngagementBloc()),
              BlocProvider<PaywallBloc>.value(value: paywall),
              _returningViewer(),
            ],
            child: ReelView(page: page, slot: slot, reel: episodes[slot]),
          ),
        ),
      );
      tester.takeException();
    }

    await pumpEpisode(6);
    expect(find.byType(ReelSurface), findsNothing);
    expect(poster, findsOneWidget);
    expect(find.byType(Paywall), findsOneWidget);

    await pumpEpisode(5);
    expect(find.byType(ReelSurface), findsOneWidget);

    // built next door while the viewer is still on the ad before it
    when(() => reels.state).thenReturn(locked.copyWith(focusedPage: 7));
    await pumpEpisode(6);
    expect(find.byType(ReelSurface), findsNothing);
    expect(find.byType(Paywall), findsNothing);

    when(() => paywall.state).thenReturn(const PaywallState(unlocked: true));
    await pumpEpisode(6);
    expect(find.byType(ReelSurface), findsOneWidget);
    expect(poster, findsNothing);

    await tester.pumpWidget(const SizedBox());
    unawaited(pool.close());
    await tester.pump();
  });
}
