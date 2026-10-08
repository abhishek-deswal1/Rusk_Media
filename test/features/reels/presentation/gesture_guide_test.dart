import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/core/ui/components/local_image_widget.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/gesture_guide.dart';
import 'package:rusk_media/features/reels/presentation/widgets/hold_indicator.dart';

class _MockOnboardingBloc extends MockBloc<OnboardingEvent, OnboardingState>
    implements OnboardingBloc {}

class _MockPoolBloc extends MockBloc<VideoPoolEvent, VideoPoolState>
    implements VideoPoolBloc {}

void main() {
  setUpAll(() => registerFallbackValue(const TipsClosed()));

  const armed = OnboardingState(swipeHintArmed: true);
  final hand = find.byType(LocalImageWidget);

  late _MockOnboardingBloc onboarding;
  late _MockPoolBloc pool;
  late ValueNotifier<bool> touching;
  late ValueNotifier<HoldReading?> demo;
  late StreamController<OnboardingState> states;
  late StreamController<VideoPoolState> poolStates;
  late List<HoldReading?> shown;

  setUp(() {
    onboarding = _MockOnboardingBloc();
    pool = _MockPoolBloc();
    poolStates = StreamController<VideoPoolState>.broadcast();
    whenListen(pool, poolStates.stream, initialState: const VideoPoolState());
    touching = ValueNotifier(false);
    demo = ValueNotifier(null);
    states = StreamController<OnboardingState>.broadcast();
    shown = [];
    demo.addListener(() => shown.add(demo.value));
  });

  tearDown(() async {
    touching.dispose();
    demo.dispose();
    await states.close();
    await poolStates.close();
  });

  Widget guide({required ValueGetter<Duration> length}) => MultiBlocProvider(
        providers: [
          BlocProvider<OnboardingBloc>.value(value: onboarding),
          BlocProvider<VideoPoolBloc>.value(value: pool),
        ],
        child: GestureGuide(touching: touching, demo: demo, length: length),
      );

  Future<void> pumpGuide(WidgetTester tester, OnboardingState initial) async {
    whenListen(onboarding, states.stream, initialState: initial);
    await tester.pumpWidget(
      MaterialApp(home: guide(length: () => const Duration(seconds: 30))),
    );
  }

  Future<void> hold(WidgetTester tester, {required bool held}) async {
    final s = VideoPoolState(held: held);
    when(() => pool.state).thenReturn(s);
    poolStates.add(s);
    await tester.pump();
  }

  Future<void> emit(WidgetTester tester, OnboardingState s) async {
    when(() => onboarding.state).thenReturn(s);
    states.add(s);
    await tester.pump();
  }

  // the guide clears the shared reading as it goes, so take it down before
  // tearDown disposes that reading, the way ReelView outlives it
  Future<void> finish(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  // frame by frame, so the hand's loops run as they do on a device
  Future<void> advance(WidgetTester tester, Duration by) async {
    for (var t = Duration.zero; t < by; t += const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('volume, then timeline, then swipe up, then it reports done',
      (tester) async {
    await pumpGuide(tester, armed);

    await tester.pump(const Duration(milliseconds: 450));
    expect(hand, findsNothing);

    // steps run 0.5-3.5s, 4-7s and 7.5-10.5s, each a press then a slide
    // out and back, twice

    // volume: the meter rises and falls with the hand
    await advance(tester, const Duration(milliseconds: 1500)); // 1.95s
    expect(hand, findsOneWidget);
    final levels = shown.whereType<VolumeReading>().map((r) => r.level);
    expect(levels.reduce((a, b) => a > b ? a : b), greaterThan(0.8));
    expect(shown.whereType<SeekReading>(), isEmpty);

    // timeline: the bar is walked forward and back
    await advance(tester, const Duration(milliseconds: 3550)); // 5.5s
    expect(demo.value, isA<SeekReading>());
    final aims = shown.whereType<SeekReading>().map((r) => r.to).toList();
    final furthest = aims.reduce((a, b) => a > b ? a : b);
    expect(furthest, greaterThan(const Duration(seconds: 20)));
    expect(aims.last, lessThan(furthest));

    // swipe: the hand alone, the bar is left to playback
    await advance(tester, const Duration(seconds: 3)); // 8.5s
    expect(hand, findsOneWidget);
    expect(demo.value, isNull);
    verifyNever(() => onboarding.add(any()));

    await advance(tester, const Duration(milliseconds: 2500)); // 11s
    expect(hand, findsNothing);
    verify(() => onboarding.add(const SwipeHintPlayed())).called(1);
    await finish(tester);
  });

  testWidgets('the hand sits in the lower right thumb zone', (tester) async {
    await pumpGuide(tester, armed);
    await advance(tester, const Duration(milliseconds: 800));

    final screen = tester.getSize(find.byType(MaterialApp));
    final at = tester.getCenter(hand);
    expect(at.dx, greaterThan(screen.width / 2));
    expect(at.dy, greaterThan(screen.height / 2));
    await finish(tester);
  });

  testWidgets('a touch skips the step on screen and clears its demo',
      (tester) async {
    await pumpGuide(tester, armed);
    await advance(tester, const Duration(milliseconds: 1200));
    expect(demo.value, isA<VolumeReading>());

    touching.value = true;
    await tester.pump();
    expect(hand, findsNothing);
    expect(demo.value, isNull);

    // nothing while the finger stays down
    await advance(tester, const Duration(seconds: 2));
    expect(hand, findsNothing);

    // lifted: after the idle gap the next step, not the skipped one
    touching.value = false;
    await advance(tester, const Duration(milliseconds: 1500));
    expect(demo.value, isA<SeekReading>());
    expect(shown.last, isA<SeekReading>());
    await finish(tester);
  });

  testWidgets('skipping every step still finishes the guide', (tester) async {
    await pumpGuide(tester, armed);
    for (var i = 0; i < 3; i++) {
      await advance(tester, const Duration(milliseconds: 800));
      expect(hand, findsOneWidget);
      touching.value = true;
      await tester.pump();
      touching.value = false;
      await tester.pump();
    }
    verify(() => onboarding.add(const SwipeHintPlayed())).called(1);
    await advance(tester, const Duration(seconds: 2));
    expect(hand, findsNothing);
    await finish(tester);
  });

  testWidgets('moving to another reel ends it and clears the demo',
      (tester) async {
    await pumpGuide(tester, armed);
    await advance(tester, const Duration(milliseconds: 1200));
    expect(demo.value, isA<VolumeReading>());

    await emit(tester, const OnboardingState());
    expect(hand, findsNothing);
    expect(demo.value, isNull);

    await advance(tester, const Duration(seconds: 6));
    expect(hand, findsNothing);
    verifyNever(() => onboarding.add(any()));
    await finish(tester);
  });

  // the pool is held while tips, the paywall or an ad are up
  testWidgets('never shows when not armed or while playback is held',
      (tester) async {
    await pumpGuide(tester, const OnboardingState());
    await advance(tester, const Duration(seconds: 2));
    expect(hand, findsNothing);

    await hold(tester, held: true);
    await emit(tester, armed);
    await advance(tester, const Duration(seconds: 2));
    expect(hand, findsNothing);
    expect(shown, isEmpty);

    await hold(tester, held: false);
    await advance(tester, const Duration(seconds: 1));
    expect(hand, findsOneWidget);

    await hold(tester, held: true);
    expect(hand, findsNothing);
    expect(shown.last, isNull);
    await finish(tester);
  });

  testWidgets('with no player yet the timeline step shows the hand only',
      (tester) async {
    whenListen(onboarding, states.stream, initialState: armed);
    await tester.pumpWidget(
      MaterialApp(home: guide(length: () => Duration.zero)),
    );
    await advance(tester, const Duration(milliseconds: 5000));
    expect(hand, findsOneWidget);
    expect(shown.whereType<SeekReading>(), isEmpty);
    await finish(tester);
  });
}
