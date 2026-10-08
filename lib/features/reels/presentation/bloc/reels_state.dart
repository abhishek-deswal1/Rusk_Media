part of 'reels_bloc.dart';

enum ReelsPhase { idle, fetching, ready, offline, broken }

// a one-off instruction for the page controller; [id] keeps two identical
// moves apart
class PageMove extends Equatable {
  const PageMove({required this.page, required this.animate, required this.id});

  final int page;
  final bool animate;
  final int id;

  @override
  List<Object?> get props => [page, animate, id];
}

class ReelsState extends BaseState {
  const ReelsState({
    this.phase = ReelsPhase.idle,
    this.reels = const [],
    this.canLoadMore = true,
    this.cursor = 0,
    this.fetchingMore = false,
    this.reloading = false,
    this.focusedPage = 0,
    this.removedSlots = const {},
    this.pageMove,
  });

  static const FeedComposer composer = FeedComposer();

  final ReelsPhase phase;
  final List<Reel> reels;
  final bool canLoadMore;
  final int cursor;
  final bool fetchingMore;
  final bool reloading;

  // a page of [items], ads included
  final int focusedPage;

  // ad slots that failed and left the feed for good
  final Set<String> removedSlots;
  final PageMove? pageMove;

  // derived, so paging and slot removal can never disagree about the feed
  List<FeedItem> get items => composer.compose(reels, removed: removedSlots);

  bool isValidPage(int page) => page >= 0 && page < items.length;

  bool get onAd {
    final all = items;
    return focusedPage < all.length && all[focusedPage] is AdSlotItem;
  }

  // catalogue index of the episode on screen, or null on an ad
  int? get focusedEpisode {
    final all = items;
    if (focusedPage >= all.length) return null;
    return switch (all[focusedPage]) {
      EpisodeItem(:final index) => index,
      AdSlotItem() => null,
    };
  }

  ReelsState copyWith({
    ReelsPhase? phase,
    List<Reel>? reels,
    bool? canLoadMore,
    int? cursor,
    bool? fetchingMore,
    bool? reloading,
    int? focusedPage,
    Set<String>? removedSlots,
    PageMove? pageMove,
  }) {
    return ReelsState(
      phase: phase ?? this.phase,
      reels: reels ?? this.reels,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      cursor: cursor ?? this.cursor,
      fetchingMore: fetchingMore ?? this.fetchingMore,
      reloading: reloading ?? this.reloading,
      focusedPage: focusedPage ?? this.focusedPage,
      removedSlots: removedSlots ?? this.removedSlots,
      pageMove: pageMove ?? this.pageMove,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        reels,
        canLoadMore,
        cursor,
        fetchingMore,
        reloading,
        focusedPage,
        removedSlots,
        pageMove,
      ];
}
