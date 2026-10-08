import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/core/video_pool/presentation/bloc/video_pool_bloc.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';
import 'package:rusk_media/features/reels/presentation/bloc/reels_bloc.dart';
import 'package:rusk_media/features/reels/presentation/screens/reels_screen.dart';

void main() {
  // E1 E2 E3 AD E4 E5 E6 AD E7 E8: page 3 is an ad, 6 is E6, 8 is E7
  final feed = ReelsState(
    phase: ReelsPhase.ready,
    reels: [
      for (var i = 1; i <= 8; i++)
        Reel(
          id: 'e$i',
          handle: '',
          caption: '',
          streamUrl: 'u$i',
          avatarUrl: '',
        ),
    ],
  );
  const locked = PaywallState();
  const open = PaywallState(unlocked: true);
  const returning = OnboardingState();
  const firstRun = OnboardingState(tipsPending: true);
  bool holds(
    ReelsState s, [
    PaywallState p = locked,
    OnboardingState o = returning,
  ]) =>
      ReelsScreen.holdsPlayback(s, p, o);

  test('a plain episode plays', () {
    expect(holds(feed.copyWith(focusedPage: 6)), isFalse);
  });

  test('an ad page holds every video', () {
    expect(holds(feed.copyWith(focusedPage: 3)), isTrue);
  });

  test('the tips hold every video once there is a reel under them', () {
    expect(holds(feed.copyWith(focusedPage: 6), locked, firstRun), isTrue);
    expect(holds(const ReelsState(), locked, firstRun), isFalse);
    expect(
      holds(const ReelsState(phase: ReelsPhase.ready), locked, firstRun),
      isFalse,
    );
  });

  test('the paywall holds while it is up, and not once unlocked', () {
    expect(holds(feed.copyWith(focusedPage: 8)), isTrue);
    expect(holds(feed.copyWith(focusedPage: 8), open), isFalse);
  });

  test('the feed can not be focused past the locked page', () {
    expect(ReelsScreen.canFocus(7, 8), isTrue);
    expect(ReelsScreen.canFocus(8, 8), isTrue);
    expect(ReelsScreen.canFocus(9, 8), isFalse);
    expect(ReelsScreen.canFocus(9, null), isTrue);
  });

  test('tips stop holding once closed, and hold before the feed settles', () {
    final closed = feed.copyWith(focusedPage: 6);
    expect(ReelsScreen.holdsPlayback(closed, locked, returning), isFalse);
    expect(
      holds(feed.copyWith(phase: ReelsPhase.fetching), locked, firstRun),
      isTrue,
    );
  });

  test('swiping to another reel or onto an ad counts as moving on', () {
    bool moved(int from, int to) => ReelsScreen.movedToAnotherReel(
          feed.copyWith(focusedPage: from),
          feed.copyWith(focusedPage: to),
        );
    expect(moved(0, 1), isTrue);
    expect(moved(2, 3), isTrue);
    expect(moved(3, 4), isTrue);
    expect(moved(1, 1), isFalse);
  });

  test('a slot dropped behind the viewer is not moving on', () {
    // on E5 at page 5; slot_1 goes and E5 is now page 4
    final before = feed.copyWith(focusedPage: 5);
    final after = feed.copyWith(focusedPage: 4, removedSlots: {'slot_1'});
    expect(ReelsScreen.movedToAnotherReel(before, after), isFalse);
  });

  test('more reels arriving is not moving on', () {
    final before = feed.copyWith(focusedPage: 6);
    final after = before.copyWith(reels: [...feed.reels, ...feed.reels]);
    expect(ReelsScreen.movedToAnotherReel(before, after), isFalse);
  });

  // E1 E2 E3 AD E4 E5 E6 AD E7 E8: page 6 is E6 (index 5), 7 the ad, 8 is E7
  group('pool window', () {
    List<int>? pages(VideoPoolWindowChanged? w) =>
        w == null ? null : [for (final s in w.slots) s.page];

    test('nothing to play before the feed is ready', () {
      expect(ReelsScreen.poolWindow(const ReelsState(), locked), isNull);
      expect(
        ReelsScreen.poolWindow(
          const ReelsState(phase: ReelsPhase.ready),
          locked,
        ),
        isNull,
      );
    });

    test('the first reel keeps one neighbour live and two warm', () {
      final w = ReelsScreen.poolWindow(feed, locked)!;
      expect(w.activePage, 0);
      expect(pages(w), [0, 1]);
      expect(w.prefetchUrls, ['u3', 'u4']);
    });

    test('the locked episode is fetched to disk but never gets a player', () {
      final w = ReelsScreen.poolWindow(feed.copyWith(focusedPage: 6), locked)!;
      expect(w.activePage, 5);
      expect(pages(w), [4, 5]);
      expect(w.prefetchUrls, ['u7']);
    });

    test('nothing past the lock is fetched', () {
      final w = ReelsScreen.poolWindow(feed.copyWith(focusedPage: 5), locked)!;
      expect(pages(w), [3, 4, 5]);
      expect(w.prefetchUrls, ['u7']);
    });

    test('unlocking opens the window and the prefetch past episode 7', () {
      final w = ReelsScreen.poolWindow(feed.copyWith(focusedPage: 6), open)!;
      expect(pages(w), [4, 5, 6]);
      expect(w.prefetchUrls, ['u8']);
    });

    test('on an ad page the window is anchored to the next episode', () {
      final w = ReelsScreen.poolWindow(feed.copyWith(focusedPage: 7), open)!;
      expect(w.activePage, 6);
      expect(pages(w), [5, 6, 7]);
      expect(w.prefetchUrls, isEmpty);
    });

    // episode 7 went to disk while E5 and E6 were on screen
    test('on the ad before the lock only the reel behind stays live', () {
      final w = ReelsScreen.poolWindow(feed.copyWith(focusedPage: 7), locked)!;
      expect(w.activePage, 6);
      expect(pages(w), [5]);
      expect(w.prefetchUrls, isEmpty);
    });
  });

  test('the paywall follows episode 7 when an ad before it goes', () {
    final dropped = feed.copyWith(removedSlots: {'slot_2'});
    expect(holds(dropped.copyWith(focusedPage: 7)), isTrue);
    expect(holds(dropped.copyWith(focusedPage: 6)), isFalse);
  });
}
