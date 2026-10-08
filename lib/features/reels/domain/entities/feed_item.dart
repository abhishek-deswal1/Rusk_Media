import 'package:equatable/equatable.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';

// one page of the feed. the key never comes from the page index: removing
// an ad slot shifts every index after it
sealed class FeedItem extends Equatable {
  const FeedItem();

  String get key;
}

final class EpisodeItem extends FeedItem {
  const EpisodeItem({required this.reel, required this.index});

  final Reel reel;

  // position in the catalogue: episode number minus one. ads never move it,
  // so players are keyed by it
  final int index;

  @override
  String get key => 'ep_${reel.id}';

  @override
  List<Object?> get props => [reel, index];
}

final class AdSlotItem extends FeedItem {
  const AdSlotItem(this.slotId);

  final String slotId;

  @override
  String get key => 'ad_$slotId';

  @override
  List<Object?> get props => [slotId];
}
