import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/ui/components/custom_text.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/hold_indicator.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_progress_bar.dart';
import 'package:rusk_media/shared/widgets/connection_state/swimming_loader.dart';

import '../../../helpers/fake_video_controller.dart';

void main() {
  final swimmer = find.byType(SwimmingLoader);

  late FakeControllerFactory factory;
  late VideoPoolBloc pool;
  late FakeVideoController player;
  late ValueNotifier<HoldReading?> hold;

  // the pool is built inside each test so its events run on the fake clock
  Future<void> pumpBar(WidgetTester tester) async {
    factory = FakeControllerFactory();
    pool = VideoPoolBloc(
      controllerFactory: factory,
      afterFrame: () async {},
      setScreenAwake: ({required enable}) async {},
    )..add(
        const VideoPoolWindowChanged(
          activePage: 0,
          slots: [VideoSlot(page: 0, url: 'u0')],
        ),
      );
    await tester.pump();
    player = factory.complete(0);
    await tester.pump();
    hold = ValueNotifier(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<VideoPoolBloc>.value(
            value: pool,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ReelProgressBar(page: 0, hold: hold),
            ),
          ),
        ),
      ),
    );
    // fonts can't load in tests; not what this checks
    tester.takeException();
  }

  Future<void> closePool(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    hold.dispose();
    unawaited(pool.close());
    await tester.pump();
  }

  final readout = find.byWidgetPredicate(
    (w) => w is CustomText && w.semanticLocator == 'progress_readout',
  );
  String readoutText(WidgetTester tester) =>
      tester.widget<CustomText>(readout).text;

  void setValue({required bool playing, required bool buffering}) {
    player.value =
        player.value.copyWith(isPlaying: playing, isBuffering: buffering);
  }

  testWidgets('a stall longer than 300ms swaps the bar for the swimmer',
      (tester) async {
    await pumpBar(tester);
    setValue(playing: true, buffering: true);

    await tester.pump(const Duration(milliseconds: 250));
    expect(swimmer, findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(swimmer, findsOneWidget);

    setValue(playing: true, buffering: false);
    await tester.pump();
    expect(swimmer, findsNothing);

    await closePool(tester);
  });

  testWidgets('a short hiccup never shows the swimmer', (tester) async {
    await pumpBar(tester);
    setValue(playing: true, buffering: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(swimmer, findsNothing);
    setValue(playing: true, buffering: false);

    await tester.pump(const Duration(seconds: 1));
    expect(swimmer, findsNothing);

    await closePool(tester);
  });

  testWidgets('a stall during a scrub keeps the bar and still seeks',
      (tester) async {
    await pumpBar(tester);
    final bar = tester.getRect(find.byType(ReelProgressBar));
    final drag =
        await tester.startGesture(bar.centerLeft + const Offset(20, 0));
    await drag.moveBy(const Offset(60, 0));
    await tester.pump();

    setValue(playing: true, buffering: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(swimmer, findsNothing);

    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await tester.pump();
    expect(player.lastSeek, isNotNull);

    await closePool(tester);
  });

  testWidgets('the bar can still be tapped to seek while the swimmer shows',
      (tester) async {
    await pumpBar(tester);
    setValue(playing: true, buffering: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(swimmer, findsOneWidget);

    final bar = tester.getRect(find.byType(ReelProgressBar));
    await tester.tapAt(bar.center);
    await tester.pump();
    expect(player.lastSeek, isNotNull);

    await closePool(tester);
  });

  testWidgets('dragging the bar shows the time as 00:05 / 00:30',
      (tester) async {
    await pumpBar(tester);
    final bar = tester.getRect(find.byType(ReelProgressBar));
    final drag = await tester.startGesture(bar.centerLeft);
    await drag.moveBy(Offset(bar.width / 6, 0));
    await tester.pump();

    expect(readoutText(tester), '00:05 / 00:30');

    await drag.up();
    await tester.pump();
    expect(readout, findsNothing);
    await closePool(tester);
  });

  testWidgets('a hold-and-slide seek elsewhere drives the bar', (tester) async {
    await pumpBar(tester);
    expect(readout, findsNothing);

    hold.value = const SeekReading(
      to: Duration(seconds: 15),
      length: Duration(seconds: 30),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(readoutText(tester), '00:15 / 00:30');

    // the time sits over the aimed point, halfway along the bar
    final bar = tester.getRect(find.byType(ReelProgressBar));
    expect(tester.getCenter(readout).dx, closeTo(bar.center.dx, 2));

    // a volume hold leaves the bar alone
    hold.value = const VolumeReading(0.5);
    await tester.pump();
    expect(readout, findsNothing);

    hold.value = null;
    await tester.pump();
    expect(readout, findsNothing);
    expect(player.lastSeek, isNull);
    await closePool(tester);
  });

  testWidgets('a seek from anywhere brings the bar back over the swimmer',
      (tester) async {
    await pumpBar(tester);
    setValue(playing: true, buffering: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(swimmer, findsOneWidget);

    hold.value = const SeekReading(
      to: Duration(seconds: 3),
      length: Duration(seconds: 30),
    );
    await tester.pump();
    expect(swimmer, findsNothing);
    expect(readoutText(tester), '00:03 / 00:30');

    hold.value = null;
    await tester.pump();
    expect(swimmer, findsOneWidget);
    await closePool(tester);
  });

  group('after a seek is let go', () {
    final paint = find.descendant(
      of: find.byType(ReelProgressBar),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
    );

    // the played part of the bar at rest: track first, then the fill
    PaintPattern fillsTo(WidgetTester tester, double share) {
      final size = tester.getSize(paint);
      final y = size.height / 2;
      return paints
        ..rrect()
        ..rrect(
          rrect: RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - 1.25, size.width * share, 2.5),
            const Radius.circular(2.5),
          ),
        );
    }

    testWidgets('a hold-and-slide seek stays on its target, not the old spot',
        (tester) async {
      await pumpBar(tester);
      expect(tester.renderObject(paint), fillsTo(tester, 0));

      // the player still reports 00:00 until its seek completes
      hold.value = const SeekLanded(
        to: Duration(seconds: 15),
        length: Duration(seconds: 30),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(readout, findsNothing);
      expect(tester.renderObject(paint), fillsTo(tester, 0.5));

      // once the player is there, it is followed again
      player.value = player.value.copyWith(
        position: const Duration(milliseconds: 15100),
      );
      await tester.pump();
      expect(tester.renderObject(paint), fillsTo(tester, 15100 / 30000));
      await closePool(tester);
    });

    testWidgets('once caught up it follows the reel playing on, no snap back',
        (tester) async {
      await pumpBar(tester);
      hold.value = const SeekLanded(
        to: Duration(seconds: 15),
        length: Duration(seconds: 30),
      );
      await tester.pump();

      // the seek completes, then playback carries on well past the target
      // while the settle window is still open
      player.value = player.value.copyWith(
        position: const Duration(seconds: 15),
      );
      await tester.pump(const Duration(milliseconds: 100));
      player.value = player.value.copyWith(
        position: const Duration(milliseconds: 15600),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.renderObject(paint), fillsTo(tester, 15600 / 30000));
      await closePool(tester);
    });

    testWidgets('a seek that never lands gives up after a second',
        (tester) async {
      await pumpBar(tester);
      hold.value = const SeekLanded(
        to: Duration(seconds: 15),
        length: Duration(seconds: 30),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.renderObject(paint), fillsTo(tester, 0.5));

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.renderObject(paint), fillsTo(tester, 0));
      await closePool(tester);
    });

    testWidgets('a drag on the bar lands the same way', (tester) async {
      await pumpBar(tester);
      // the native seek is still on its way, the player says 00:00
      player.seekLands = false;
      final bar = tester.getRect(find.byType(ReelProgressBar));
      await tester.dragFrom(bar.centerLeft, Offset(bar.width / 2, 0));
      // let the bar spring back to its resting thickness, inside the
      // one-second landing window
      for (var i = 0; i < 36; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(player.lastSeek, isNotNull);

      final size = tester.getSize(paint);
      final share = (bar.width / 2) / size.width;
      expect(tester.renderObject(paint), fillsTo(tester, share));
      await closePool(tester);
    });

    testWidgets('a cancelled hold never pretends to land', (tester) async {
      await pumpBar(tester);
      hold.value = const SeekReading(
        to: Duration(seconds: 15),
        length: Duration(seconds: 30),
      );
      await tester.pump();
      hold.value = null;
      // let the bar spring back to its resting thickness first
      for (var i = 0; i < 36; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.renderObject(paint), fillsTo(tester, 0));
      await closePool(tester);
    });
  });

  testWidgets('grabbing the bar swells it on a spring and lets it settle',
      (tester) async {
    await pumpBar(tester);
    final paint = find.descendant(
      of: find.byType(ReelProgressBar),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
    );
    // the track is the first rounded rect painted; its height is the bar's
    double thickness() {
      double? first;
      expect(
        tester.renderObject(paint),
        paints
          ..everything((method, args) {
            if (method == #drawRRect) first ??= (args[0] as RRect).height;
            return true;
          }),
      );
      return first!;
    }

    expect(thickness(), 2.5);
    final bar = tester.getRect(find.byType(ReelProgressBar));
    final drag = await tester.startGesture(bar.centerLeft);
    await drag.moveBy(const Offset(40, 0));

    final grabbed = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      grabbed.add(thickness());
    }
    // past the target, then back onto it exactly
    expect(grabbed.reduce((a, b) => a > b ? a : b), greaterThan(5.1));
    expect(grabbed.last, 5);

    await drag.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(thickness(), 2.5);
    await closePool(tester);
  });

  testWidgets('the bar is painted, behind its own repaint boundary',
      (tester) async {
    await pumpBar(tester);
    final paint = find.descendant(
      of: find.byType(ReelProgressBar),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
    );
    expect(paint, findsOneWidget);
    expect(
      find.ancestor(of: paint, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    await closePool(tester);
  });

  testWidgets('buffering while paused keeps the normal bar', (tester) async {
    await pumpBar(tester);
    setValue(playing: false, buffering: true);

    await tester.pump(const Duration(seconds: 1));
    expect(swimmer, findsNothing);

    await closePool(tester);
  });
}
