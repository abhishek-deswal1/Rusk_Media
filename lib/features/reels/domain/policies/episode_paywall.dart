import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';

// the free run ends at one episode; it and everything after it stay locked
// until the viewer unlocks
class EpisodePaywall {
  const EpisodePaywall({this.lockedEpisode = 7});

  final int lockedEpisode;

  // catalogue index of the locked episode, once the feed has loaded that far
  int? lockedIndex(int loaded) =>
      lockedEpisode > 0 && loaded >= lockedEpisode ? lockedEpisode - 1 : null;

  bool isLockedEpisode(int episodeIndex) =>
      lockedEpisode > 0 && episodeIndex == lockedEpisode - 1;

  // the locked episode and anything after it never get a player
  bool locks(int episodeIndex) =>
      lockedEpisode > 0 && episodeIndex >= lockedEpisode - 1;

  // follows the episode, so dropping an ad slot before it moves the page too
  int? lockedPage(List<FeedItem> items) {
    final page =
        items.indexWhere((e) => e is EpisodeItem && isLockedEpisode(e.index));
    return page == -1 ? null : page;
  }
}
