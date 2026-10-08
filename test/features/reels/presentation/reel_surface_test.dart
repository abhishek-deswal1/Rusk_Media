import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rusk_media/core/constants/app_strings.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/presentation/widgets/reel_surface.dart';
import 'package:rusk_media/shared/widgets/connection_state/connection_state_view.dart';
import 'package:video_player/video_player.dart';

import '../../../helpers/fake_video_controller.dart';

void main() {
  final loader = find.byType(ConnectionStateView);

  late FakeControllerFactory factory;
  late VideoPoolBloc pool;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // the pool is built inside each test so its events run on the fake clock
  Future<void> openWindow(WidgetTester tester, {required int active}) async {
    factory = FakeControllerFactory();
    pool = VideoPoolBloc(
      controllerFactory: factory,
      afterFrame: () async {},
      setScreenAwake: ({required enable}) async {},
    )..add(
        VideoPoolWindowChanged(
          activePage: active,
          slots: const [
            VideoSlot(page: 0, url: 'u0'),
            VideoSlot(page: 1, url: 'u1'),
          ],
        ),
      );
    await tester.pump();
  }

  Future<void> pumpSurface(WidgetTester tester, int page) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<VideoPoolBloc>.value(
          value: pool,
          child: ReelSurface(page: page),
        ),
      ),
    );
    // fonts can't load in tests; not what this checks
    tester.takeException();
  }

  bool ticking(WidgetTester tester) => TickerMode.of(tester.element(loader));

  Future<void> closePool(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    unawaited(pool.close());
    await tester.pump();
  }

  testWidgets('a reel that is still loading shows the loading screen',
      (tester) async {
    await openWindow(tester, active: 0);
    await pumpSurface(tester, 0);
    expect(loader, findsOneWidget);
    expect(find.text(AppStrings.loadingHeading), findsWidgets);

    factory.complete(0);
    await tester.pump();
    expect(loader, findsNothing);
    expect(find.byType(VideoPlayer), findsOneWidget);

    await closePool(tester);
  });

  testWidgets('a failed reel keeps its retry card', (tester) async {
    await openWindow(tester, active: 0);
    await pumpSurface(tester, 0);
    factory.fail(0);
    await tester.pump();
    tester.takeException();

    expect(loader, findsNothing);
    expect(find.text(AppStrings.reelRetry), findsOneWidget);

    await closePool(tester);
  });

  testWidgets('only the focused reel animates, and not under the first cover',
      (tester) async {
    await openWindow(tester, active: 0);
    await pumpSurface(tester, 0);
    // first reel still loading: the full-screen cover is on top of it
    expect(ticking(tester), isFalse);

    factory.complete(0);
    await tester.pump();
    await pumpSurface(tester, 1);
    // neighbour, built offscreen
    expect(loader, findsOneWidget);
    expect(ticking(tester), isFalse);

    pool.add(
      const VideoPoolWindowChanged(
        activePage: 1,
        slots: [
          VideoSlot(page: 0, url: 'u0'),
          VideoSlot(page: 1, url: 'u1'),
        ],
      ),
    );
    await tester.pump();
    expect(ticking(tester), isTrue);

    await closePool(tester);
  });
}
