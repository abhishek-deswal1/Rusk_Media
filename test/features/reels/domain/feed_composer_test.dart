import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/policies/feed_composer.dart';

void main() {
  Reel ep(int n) => Reel(
        id: 'e$n',
        handle: '',
        caption: 'Episode $n',
        streamUrl: 'u$n',
        avatarUrl: '',
      );

  const composer = FeedComposer();
  final seven = [for (var n = 1; n <= 7; n++) ep(n)];
  final feed = composer.compose(seven);
  List<String> keys(List<FeedItem> items) => [for (final i in items) i.key];

  test('seven episodes read E1 E2 E3 AD E4 E5 E6 AD E7', () {
    expect(keys(feed), [
      'ep_e1', 'ep_e2', 'ep_e3', 'ad_slot_1', //
      'ep_e4', 'ep_e5', 'ep_e6', 'ad_slot_2', 'ep_e7',
    ]);
  });

  test('while more is due the feed ends in a last page, not an ad', () {
    // six episodes loaded, more on the way: no slot_2 yet, a last page instead
    final due = composer.compose(seven.take(6).toList(), more: true);
    expect(keys(due).skip(6), ['ep_e6', 'more']);
    // the catalogue is done: nothing after the last episode
    expect(keys(composer.compose(seven)).last, 'ep_e7');
    // nothing loaded yet: no feed, so no last page either
    expect(composer.compose(const [], more: true), isEmpty);
  });

  test('ad slots never change episode numbering', () {
    final episodes = feed.whereType<EpisodeItem>();
    expect([for (final e in episodes) e.index], [0, 1, 2, 3, 4, 5, 6]);
    final captions = [for (final e in episodes) e.reel.caption];
    expect(captions, [for (var n = 1; n <= 7; n++) 'Episode $n']);
  });

  test('no slot after the last loaded episode, so paging only adds ahead', () {
    final firstBatch = composer.compose(seven.take(3).toList());
    expect(keys(firstBatch), ['ep_e1', 'ep_e2', 'ep_e3']);
    expect(keys(composer.compose(seven.take(6).toList())).last, 'ep_e6');
    expect(composer.compose(const []), isEmpty);
  });

  test('a removed slot is left out and the others keep their ids', () {
    final items = composer.compose(seven, removed: {'slot_1'});
    expect(keys(items), [
      'ep_e1', 'ep_e2', 'ep_e3', 'ep_e4', //
      'ep_e5', 'ep_e6', 'ad_slot_2', 'ep_e7',
    ]);
  });

  test('slots load from the current page up to three pages on', () {
    expect(composer.slotsToLoad(feed, current: 0, ahead: 3), ['slot_1']);
    expect(composer.slotsToLoad(feed, current: 3, ahead: 3), ['slot_1']);
    expect(composer.slotsToLoad(feed, current: 4, ahead: 3), ['slot_2']);
    expect(composer.slotsToLoad(feed, current: 8, ahead: 3), isEmpty);
  });

  group('removing a failed slot', () {
    test('ahead of the viewer: no page change', () {
      final plan = composer.planRemoval(feed, slotId: 'slot_1', current: 1);
      expect(plan, isA<RemoveSlot>());
      plan as RemoveSlot;
      expect(plan.jump, isFalse);
      expect(plan.current, 1);
    });

    test('behind the viewer: same episode, page corrected by one', () {
      // on E5, page 5
      final plan = composer.planRemoval(feed, slotId: 'slot_1', current: 5);
      plan as RemoveSlot;
      expect(plan.jump, isTrue);
      expect(plan.current, 4);
      final after = composer.compose(seven, removed: {'slot_1'});
      expect(after[plan.current].key, 'ep_e5');
    });

    test('under the viewer: glide on first', () {
      final plan = composer.planRemoval(feed, slotId: 'slot_1', current: 3);
      expect(plan, isA<MoveOffSlot>());
      expect((plan as MoveOffSlot).target, 4);
    });

    test('unknown or already gone: just dropped', () {
      expect(
        composer.planRemoval(feed, slotId: 'nope', current: 0),
        isA<DropSlot>(),
      );
    });

    test('the only page there is: kept until there is somewhere to go', () {
      const single = [AdSlotItem('slot_1')];
      expect(
        composer.planRemoval(single, slotId: 'slot_1', current: 0),
        isA<KeepSlot>(),
      );
    });
  });
}
