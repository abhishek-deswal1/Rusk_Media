import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';

// lays ad slots into the episode list and plans how a failed slot leaves the
// feed without anything on screen moving
class FeedComposer {
  const FeedComposer({this.adEvery = 3});

  final int adEvery;

  // for seven episodes: E1 E2 E3 AD E4 E5 E6 AD E7. no slot after the last
  // loaded episode, so the next page can only grow the feed ahead of the
  // viewer. while [more] is on the way a last page stands in for it, so the
  // feed never just stops; it becomes whatever the next batch puts there
  List<FeedItem> compose(
    List<Reel> reels, {
    Set<String> removed = const {},
    bool more = false,
  }) {
    final items = <FeedItem>[];
    for (var i = 0; i < reels.length; i++) {
      items.add(EpisodeItem(reel: reels[i], index: i));
      final last = i == reels.length - 1;
      if (adEvery > 0 && (i + 1) % adEvery == 0 && !last) {
        final slotId = 'slot_${(i + 1) ~/ adEvery}';
        if (!removed.contains(slotId)) items.add(AdSlotItem(slotId));
      }
    }
    if (more && reels.isNotEmpty) items.add(const MoreItem());
    return List.unmodifiable(items);
  }

  // slots that should be loading now: on screen or up to [ahead] pages on
  List<String> slotsToLoad(
    List<FeedItem> items, {
    required int current,
    required int ahead,
  }) =>
      [
        for (var i = current; i <= current + ahead && i < items.length; i++)
          if (items[i] case AdSlotItem(:final slotId)) slotId,
      ];

  SlotRemoval planRemoval(
    List<FeedItem> items, {
    required String slotId,
    required int current,
  }) {
    final at = items.indexWhere((e) => e is AdSlotItem && e.slotId == slotId);
    if (at == -1) return const DropSlot();

    // the viewer is looking at it: glide them off first, it goes once they
    // have settled somewhere else
    if (at == current) {
      final target = at + 1 < items.length ? at + 1 : at - 1;
      if (target < 0) return const KeepSlot();
      return MoveOffSlot(target);
    }

    // a slot behind the viewer shifts their page down by one; the page is
    // corrected in the same frame so nothing visibly moves
    final behind = at < current;
    return RemoveSlot(
      current: behind ? current - 1 : current,
      jump: behind,
    );
  }
}

sealed class SlotRemoval {
  const SlotRemoval();
}

// not in the feed (yet or any more): just never show it
final class DropSlot extends SlotRemoval {
  const DropSlot();
}

// the only page there is; leave it until there is somewhere to go
final class KeepSlot extends SlotRemoval {
  const KeepSlot();
}

final class RemoveSlot extends SlotRemoval {
  const RemoveSlot({required this.current, required this.jump});

  final int current;
  final bool jump;
}

final class MoveOffSlot extends SlotRemoval {
  const MoveOffSlot(this.target);

  final int target;
}
