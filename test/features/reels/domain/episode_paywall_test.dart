import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/policies/episode_paywall.dart';
import 'package:rusk_media/features/reels/domain/policies/feed_composer.dart';

List<FeedItem> _feed(int episodes, {Set<String> removed = const {}}) =>
    const FeedComposer().compose(
      [
        for (var i = 0; i < episodes; i++)
          Reel(
            id: 'e$i',
            handle: '',
            caption: '',
            streamUrl: 'https://x/e$i.mp4',
            avatarUrl: '',
          ),
      ],
      removed: removed,
    );

void main() {
  const paywall = EpisodePaywall();

  test('nothing is locked until the locked episode has loaded', () {
    expect(paywall.lockedIndex(0), isNull);
    expect(paywall.lockedIndex(6), isNull);
  });

  test('episode 7 is catalogue index 6', () {
    expect(paywall.lockedIndex(7), 6);
    expect(paywall.lockedIndex(30), 6);
    expect(paywall.isLockedEpisode(6), isTrue);
    expect(paywall.isLockedEpisode(5), isFalse);
    expect(paywall.isLockedEpisode(7), isFalse);
  });

  test('another episode can be chosen', () {
    expect(const EpisodePaywall(lockedEpisode: 3).lockedIndex(5), 2);
    expect(const EpisodePaywall(lockedEpisode: 0).lockedIndex(5), isNull);
    expect(const EpisodePaywall(lockedEpisode: 0).locks(9), isFalse);
    expect(const EpisodePaywall(lockedEpisode: 0).isLockedEpisode(-1), isFalse);
  });

  test('episode 7 and everything after it are locked', () {
    final locked = [for (var i = 0; i < 9; i++) paywall.locks(i)];
    expect(
      locked,
      [false, false, false, false, false, false, true, true, true],
    );
  });

  // E1 E2 E3 AD E4 E5 E6 AD E7 E8: page 8 is E7
  test('the locked page is where episode 7 sits in the feed', () {
    expect(paywall.lockedPage(_feed(6)), isNull);
    expect(paywall.lockedPage(_feed(7)), 8);
    expect(paywall.lockedPage(_feed(8)), 8);
  });

  test('the locked page follows episode 7 when an ad before it goes', () {
    expect(paywall.lockedPage(_feed(8, removed: {'slot_2'})), 7);
    expect(paywall.lockedPage(_feed(8, removed: {'slot_1', 'slot_2'})), 6);
  });
}
