import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/ads/ad_preloader.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/ad_page.dart';
import 'package:rusk_media/shared/widgets/connection_state/connection_state_view.dart';

class _MockReelsBloc extends MockBloc<ReelsEvent, ReelsState>
    implements ReelsBloc {}

class _SilentAd extends NativeAd {
  _SilentAd(NativeAdListener listener)
      : super(
          adUnitId: 'test',
          factoryId: 'test',
          listener: listener,
          request: const AdRequest(),
        );

  @override
  Future<void> load() async {}

  @override
  Future<void> dispose() async {}

  void answer() => listener.onAdLoaded!(this);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final page = find.byType(AdPage);
  final loading = find.byType(ConnectionStateView);
  final opened = <AdPreloader>[];
  final made = <_SilentAd>[];

  // the native view can't exist in a test; AdWidget complains and is drawn
  // as an error box, while everything around it behaves as on a device
  Future<void> pumpQuietly(WidgetTester tester, [Duration? by]) async {
    await tester.pump(by);
    tester.takeException();
  }

  double opacityOf(WidgetTester tester, Finder child) => tester
      .widget<FadeTransition>(
        find.ancestor(of: child, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;

  Future<AdPreloader> pumpAd(
    WidgetTester tester, {
    required int focused,
  }) async {
    final reels = _MockReelsBloc();
    when(() => reels.state).thenReturn(
      ReelsState(phase: ReelsPhase.ready, focusedPage: focused),
    );
    final ads = AdPreloader(
      createAd: (_, listener) {
        final ad = _SilentAd(listener);
        made.add(ad);
        return ad;
      },
    )..load(['slot_1']);
    opened.add(ads);
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<AdPreloader>.value(
          value: ads,
          child: BlocProvider<ReelsBloc>.value(
            value: reels,
            child: const AdPage(page: 3, slotId: 'slot_1'),
          ),
        ),
      ),
    );
    // fonts can't load in tests; not what this checks
    tester.takeException();
    return ads;
  }

  // the load timeout is a real timer; it has to go before the test ends
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.takeException();
    for (final ads in opened) {
      ads.dispose();
    }
    opened.clear();
    made.clear();
  }

  testWidgets('while the ad loads it shows the same screen as a video',
      (tester) async {
    await pumpAd(tester, focused: 3);
    expect(find.descendant(of: page, matching: loading), findsOneWidget);
    await finish(tester);
  });

  testWidgets('has no episode gestures of its own', (tester) async {
    await pumpAd(tester, focused: 3);
    expect(
      find.descendant(of: page, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    await finish(tester);
  });

  testWidgets('only animates while it is the page on screen', (tester) async {
    await pumpAd(tester, focused: 2);
    expect(TickerMode.of(tester.element(loading)), isFalse);

    await pumpAd(tester, focused: 3);
    expect(TickerMode.of(tester.element(loading)), isTrue);
    await finish(tester);
  });

  testWidgets('an ad landing on screen: the loading screen fades off it',
      (tester) async {
    await pumpAd(tester, focused: 3);
    made.last.answer();
    await pumpQuietly(tester);
    expect(find.byType(AdWidget), findsOneWidget);

    // the native view is never under a fade, a slide or a transform
    for (final type in [FadeTransition, SlideTransition, Transform, Opacity]) {
      expect(
        find.ancestor(of: find.byType(AdWidget), matching: find.byType(type)),
        findsNothing,
      );
    }

    await pumpQuietly(tester, const Duration(milliseconds: 160));
    expect(opacityOf(tester, loading), inExclusiveRange(0.0, 1.0));
    // the chip and hint come in too
    expect(opacityOf(tester, find.text('Sponsored')), lessThan(1));

    await pumpQuietly(tester, const Duration(milliseconds: 400));
    await pumpQuietly(tester);
    expect(loading, findsNothing);
    expect(opacityOf(tester, find.text('Sponsored')), 1);
    await finish(tester);
  });

  testWidgets('an ad that lands off screen is simply there on arrival',
      (tester) async {
    await pumpAd(tester, focused: 2);
    made.last.answer();
    await pumpQuietly(tester);
    await pumpQuietly(tester);

    expect(loading, findsNothing);
    expect(opacityOf(tester, find.text('Sponsored')), 1);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('on a short screen the ad gives way, nothing runs off screen',
      (tester) async {
    tester.view
      ..physicalSize = const Size(360, 520)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpAd(tester, focused: 2);
    made.last.answer();
    await pumpQuietly(tester);
    await pumpQuietly(tester);

    final hint = find.text(AppStrings.adSwipeOn);
    expect(tester.getBottomLeft(hint).dy, lessThanOrEqualTo(520));
    final ad = tester.getRect(find.byType(AdWidget));
    expect(ad.bottom, lessThan(tester.getTopLeft(hint).dy));
    await finish(tester);
  });

  testWidgets('a released slot still looks like loading, never broken',
      (tester) async {
    final ads = await pumpAd(tester, focused: 3);
    ads.release('slot_1');
    await tester.pump();
    expect(loading, findsOneWidget);
    await finish(tester);
  });
}
