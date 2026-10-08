import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/paywall_layer.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final title = find.text(AppStrings.unlockTitle);
  final cta = find.text(AppStrings.unlockCta);
  final sweep = find.descendant(
    of: find.byType(ShimmerButton),
    matching: find.byType(ShaderMask),
  );

  Future<void> pumpPaywall(
    WidgetTester tester, {
    required bool visible,
    VoidCallback? onUnlock,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Paywall(visible: visible, onUnlock: onUnlock ?? () {}),
        ),
      ),
    );
    // fonts can't load in tests; not what this checks
    tester.takeException();
  }

  group('on the feed', () {
    late PaywallBloc paywall;

    setUp(() => paywall = PaywallBloc());
    tearDown(() => paywall.close());

    Future<void> pumpLayer(
      WidgetTester tester, {
      required int episode,
      required bool focused,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: paywall,
              child: PaywallLayer(episode: episode, focused: focused),
            ),
          ),
        ),
      );
      tester.takeException();
    }

    testWidgets('swiping off the locked reel plays the leave, no cut',
        (tester) async {
      await pumpLayer(tester, episode: 6, focused: true);
      await tester.pump(const Duration(seconds: 1));
      expect(title, findsOneWidget);

      // focus moves at the half-page point while the page is still on screen
      await pumpLayer(tester, episode: 6, focused: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(title, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(title, findsNothing);

      // and the next visit comes in again
      await pumpLayer(tester, episode: 6, focused: true);
      await tester.pump(const Duration(seconds: 1));
      expect(title, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only the locked episode ever builds a paywall',
        (tester) async {
      await pumpLayer(tester, episode: 5, focused: true);
      expect(find.byType(Paywall), findsNothing);
      await pumpLayer(tester, episode: 7, focused: true);
      expect(find.byType(Paywall), findsNothing);
    });

    testWidgets('unlocking takes it away while still focused', (tester) async {
      await pumpLayer(tester, episode: 6, focused: true);
      await tester.pump(const Duration(seconds: 1));
      expect(title, findsOneWidget);

      // the bloc lives outside the test's fake clock
      await tester.runAsync(() async {
        paywall.add(const PaywallUnlocked());
        await pumpEventQueue();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(title, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('comes in over a live blur and bounces past its rest spot',
      (tester) async {
    await pumpPaywall(tester, visible: true);
    expect(find.byType(BackdropFilter), findsOneWidget);

    var highest = double.infinity;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      highest = highest < tester.getTopLeft(title).dy
          ? highest
          : tester.getTopLeft(title).dy;
    }
    final rest = tester.getTopLeft(title).dy;
    expect(highest, lessThan(rest - 4));
    expect(cta, findsOneWidget);
  });

  testWidgets('unlocks after the purchase delay, once, without a spinner',
      (tester) async {
    var unlocks = 0;
    await pumpPaywall(tester, visible: true, onUnlock: () => unlocks++);
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(cta);
    await tester.pump();
    expect(find.text(AppStrings.unlocking), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // a second tap while unlocking does nothing
    await tester.tap(find.text(AppStrings.unlocking));
    await tester.pump(Paywall.unlockDelay - const Duration(milliseconds: 1));
    expect(unlocks, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(unlocks, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(unlocks, 1);
  });

  testWidgets('slides away once it is no longer needed', (tester) async {
    await pumpPaywall(tester, visible: true);
    await tester.pump(const Duration(seconds: 1));

    await pumpPaywall(tester, visible: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(title, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(title, findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('the button shimmers for 1.2s out of every 3s', (tester) async {
    await pumpPaywall(tester, visible: true);

    // frame by frame, as on a device, so the sweep ends when it should
    Future<void> advance(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await advance(600);
    expect(sweep, findsOneWidget);
    await advance(1400);
    expect(sweep, findsNothing);
    await advance(1600);
    expect(sweep, findsOneWidget);
  });

  testWidgets('taps stop at the paywall but swipes still reach the feed',
      (tester) async {
    final pages = PageController();
    var tapsBelow = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: pages,
          scrollDirection: Axis.vertical,
          children: [
            Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(onTap: () => tapsBelow++),
                Paywall(visible: true, onUnlock: () {}),
              ],
            ),
            const SizedBox.expand(),
          ],
        ),
      ),
    );
    tester.takeException();
    await tester.pump(const Duration(seconds: 1));

    await tester.tapAt(const Offset(200, 100));
    await tester.pump();
    expect(tapsBelow, 0);

    // back in the feed means a swipe, so it has to get through
    await tester.dragFrom(const Offset(200, 200), const Offset(0, -400));
    // the shimmer never settles, so step the snap frame by frame
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pages.page, 1);
    pages.dispose();
  });
}
