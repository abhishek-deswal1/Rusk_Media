import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/video_pool/domain/video_slot.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';

import '../../helpers/fake_video_controller.dart';

void main() {
  late FakeControllerFactory factory;
  late Completer<void> frame;
  late List<bool> awake;
  late VideoPoolBloc pool;

  VideoPoolWindowChanged window(int active, List<int> pages) =>
      VideoPoolWindowChanged(
        activePage: active,
        slots: [for (final p in pages) VideoSlot(page: p, url: 'u$p')],
      );

  setUp(() {
    factory = FakeControllerFactory();
    frame = Completer<void>();
    awake = [];
    pool = VideoPoolBloc(
      controllerFactory: factory,
      afterFrame: () => frame.future,
      setScreenAwake: ({required enable}) async => awake.add(enable),
    );
  });

  tearDown(() => pool.close());

  test('requests the active page first, then neighbours', () async {
    pool.add(window(1, [0, 1, 2]));
    await pumpEventQueue();

    expect(factory.requestedUrls, ['u1', 'u0', 'u2']);
    expect(pool.state.loading, {0, 1, 2});
  });

  test('plays the active video once ready and keeps neighbours paused',
      () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final active = factory.complete(0);
    final neighbour = factory.complete(1);
    await pumpEventQueue();

    expect(active.value.isPlaying, isTrue);
    expect(neighbour.value.isPlaying, isFalse);
    expect(pool.state.hasStarted, isTrue);
    expect(awake.last, isTrue);
  });

  test('drops and disposes a load that finishes after its page left', () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    pool.add(window(3, [3]));
    await pumpEventQueue();

    final stale = factory.complete(1);
    await pumpEventQueue();

    expect(stale.disposed, isTrue);
    expect(pool.state.controllers.containsKey(1), isFalse);
  });

  test('a page re-requested after leaving ignores its first load', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    pool.add(window(5, [5]));
    await pumpEventQueue();
    pool.add(window(0, [0]));
    await pumpEventQueue();

    final first = factory.complete(0);
    await pumpEventQueue();
    expect(first.disposed, isTrue);
    expect(pool.state.controllers[0], isNull);

    final second = factory.complete(2);
    await pumpEventQueue();
    expect(pool.state.controllers[0], same(second));
  });

  test('controllers leaving the window are disposed only after the frame',
      () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    factory.complete(1);
    await pumpEventQueue();

    pool.add(window(1, [1, 2]));
    await pumpEventQueue();

    expect(pool.state.controllers.containsKey(0), isFalse);
    expect(page0.disposed, isFalse);

    frame.complete();
    await pumpEventQueue();
    expect(page0.disposed, isTrue);
  });

  test('a failed load can be retried', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    factory.fail(0);
    await pumpEventQueue();
    expect(pool.state.failed, {0});

    pool.add(const VideoPoolRetryRequested(0));
    await pumpEventQueue();
    expect(pool.state.failed, isEmpty);
    expect(factory.requestedUrls, ['u0', 'u0']);

    factory.complete(1);
    await pumpEventQueue();
    expect(pool.state.controllers[0], isNotNull);
  });

  test('a hold or backgrounding pauses, releasing resumes', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final active = factory.complete(0);
    await pumpEventQueue();

    pool.add(const VideoPoolHoldChanged(held: true));
    await pumpEventQueue();
    expect(active.value.isPlaying, isFalse);
    expect(awake.last, isFalse);

    pool
      ..add(const VideoPoolHoldChanged(held: false))
      ..add(const VideoPoolAppBackgrounded());
    await pumpEventQueue();
    expect(active.value.isPlaying, isFalse);

    pool.add(const VideoPoolAppForegrounded());
    await pumpEventQueue();
    expect(active.value.isPlaying, isTrue);
  });

  test('a player that dies after it is ready is let go and marked failed',
      () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final active = factory.complete(0);
    await pumpEventQueue();
    expect(active.value.isPlaying, isTrue);

    active.fail('source error');
    await pumpEventQueue();
    expect(pool.state.failed, {0});
    expect(pool.state.controllers, isEmpty);
    expect(awake.last, isFalse);

    // the retry card asks for a fresh player
    pool.add(const VideoPoolRetryRequested(0));
    await pumpEventQueue();
    expect(factory.requestedUrls, ['u0', 'u0']);
    expect(pool.state.failed, isEmpty);

    // the dead player is still around until the frame ends; it reporting
    // again must not fail the fresh load
    active.fail('again');
    await pumpEventQueue();
    expect(pool.state.failed, isEmpty);
    expect(factory.requestedUrls, ['u0', 'u0']);

    frame.complete();
    await pumpEventQueue();
    expect(active.disposed, isTrue);
  });

  test('a player dying after its page left is ignored', () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final left = factory.complete(1);
    await pumpEventQueue();

    pool.add(window(0, [0]));
    await pumpEventQueue();
    left.fail('late');
    await pumpEventQueue();
    expect(pool.state.failed, isEmpty);
  });

  test('backgrounding pauses even while native playback is suppressed',
      () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final active = factory.complete(0);
    final neighbour = factory.complete(1);
    await pumpEventQueue();
    final before = (active.pauses, neighbour.pauses);

    // a ringing call takes audio focus: the player reports stopped but will
    // resume by itself once focus comes back
    active.suppress();
    neighbour.suppress();
    pool.add(const VideoPoolAppBackgrounded());
    await pumpEventQueue();
    expect(active.pauses, before.$1 + 1);
    expect(neighbour.pauses, before.$2 + 1);
  });

  test('a user pause survives a hold and a trip to the background', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final active = factory.complete(0);
    await pumpEventQueue();

    pool.add(const VideoPoolPlaybackToggled());
    await pumpEventQueue();
    expect(active.value.isPlaying, isFalse);
    final pauses = active.pauses;

    pool
      ..add(const VideoPoolHoldChanged(held: true))
      ..add(const VideoPoolHoldChanged(held: false))
      ..add(const VideoPoolAppBackgrounded())
      ..add(const VideoPoolAppForegrounded());
    await pumpEventQueue();
    expect(active.value.isPlaying, isFalse);
    expect(pool.state.userPaused, isTrue);
    expect(awake.last, isFalse);
    // each step re-asserts the pause rather than trusting the last reading
    expect(active.pauses, pauses + 4);
  });

  test('user pause resets on swipe and a revisited page restarts', () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    final page1 = factory.complete(1);
    await pumpEventQueue();
    await page0.seekTo(const Duration(seconds: 5));

    pool.add(const VideoPoolPlaybackToggled());
    await pumpEventQueue();
    expect(pool.state.userPaused, isTrue);

    pool.add(window(1, [0, 1]));
    await pumpEventQueue();
    expect(pool.state.userPaused, isFalse);
    expect(page1.value.isPlaying, isTrue);

    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    expect(page0.lastSeek, Duration.zero);
    expect(page0.value.isPlaying, isTrue);
    expect(page1.value.isPlaying, isFalse);
  });

  test('mute toggles back to the last volume on every controller', () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    final page1 = factory.complete(1);
    await pumpEventQueue();

    pool.add(const VideoPoolVolumeChanged(0.4));
    await pumpEventQueue();
    pool.add(const VideoPoolMuteToggled());
    await pumpEventQueue();
    expect(pool.state.volume, 0);
    expect(page1.volume, 0);

    pool.add(const VideoPoolMuteToggled());
    await pumpEventQueue();
    expect(pool.state.volume, 0.4);
    expect(page0.volume, 0.4);
  });

  test('seek is clamped to the video length', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    await pumpEventQueue();

    pool.add(
      const VideoPoolSeekRequested(page: 0, position: Duration(minutes: 5)),
    );
    await pumpEventQueue();
    expect(page0.lastSeek, const Duration(seconds: 30));
  });

  test('close disposes every controller it still holds', () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    final page1 = factory.complete(1);
    await pumpEventQueue();

    await pool.close();
    expect(page0.disposed, isTrue);
    expect(page1.disposed, isTrue);
  });

  test('a load finishing after close is disposed', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    await pool.close();

    final late = factory.complete(0);
    await pumpEventQueue();
    expect(late.disposed, isTrue);
  });

  test('becoming active on an already-ready neighbour counts as started',
      () async {
    pool.add(window(0, [0, 1]));
    await pumpEventQueue();
    factory
      ..fail(0)
      ..complete(1);
    await pumpEventQueue();
    expect(pool.state.hasStarted, isFalse);

    pool.add(window(1, [0, 1, 2]));
    await pumpEventQueue();
    expect(pool.state.hasStarted, isTrue);
  });

  test('volume is clamped to 0..1 on state and controllers', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final page0 = factory.complete(0);
    await pumpEventQueue();

    pool.add(const VideoPoolVolumeChanged(0.5));
    await pumpEventQueue();
    pool.add(const VideoPoolVolumeChanged(1.7));
    await pumpEventQueue();
    expect(pool.state.volume, 1);
    expect(page0.volume, 1);

    pool.add(const VideoPoolVolumeChanged(-0.3));
    await pumpEventQueue();
    expect(pool.state.volume, 0);
    expect(page0.volume, 0);

    // unmuting brings back the clamped level, never 1.7 or 0
    pool.add(const VideoPoolMuteToggled());
    await pumpEventQueue();
    expect(pool.state.volume, 1);
    expect(page0.volume, 1);
  });

  test('prefetch urls are handed to the factory', () async {
    pool.add(
      const VideoPoolWindowChanged(
        activePage: 0,
        slots: [VideoSlot(page: 0, url: 'u0')],
        prefetchUrls: ['p2', 'p3'],
      ),
    );
    await pumpEventQueue();
    expect(factory.prefetched, ['p2', 'p3']);
  });

  test('a page whose url changed gets a fresh controller', () async {
    pool.add(window(0, [0]));
    await pumpEventQueue();
    final old = factory.complete(0);
    await pumpEventQueue();

    pool.add(
      const VideoPoolWindowChanged(
        activePage: 0,
        slots: [VideoSlot(page: 0, url: 'other')],
      ),
    );
    await pumpEventQueue();
    expect(factory.requestedUrls, ['u0', 'other']);
    expect(pool.state.controllers[0], isNull);

    frame.complete();
    await pumpEventQueue();
    expect(old.disposed, isTrue);

    final fresh = factory.complete(1);
    await pumpEventQueue();
    expect(pool.state.controllers[0], same(fresh));
  });
}
