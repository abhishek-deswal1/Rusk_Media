part of 'reels_bloc.dart';

sealed class ReelsEvent extends BaseEvent {
  const ReelsEvent();
}

final class ReelsOpened extends ReelsEvent {
  const ReelsOpened();
}

final class ReelsReloadRequested extends ReelsEvent {
  const ReelsReloadRequested();
}

// the retry on the last page, when the next batch couldn't be fetched
final class ReelsMoreRequested extends ReelsEvent {
  const ReelsMoreRequested();
}

final class ReelFocused extends ReelsEvent {
  const ReelFocused(this.page);

  final int page;

  @override
  List<Object?> get props => [page];
}

// an ad slot errored, came back empty or timed out
final class AdSlotFailed extends ReelsEvent {
  const AdSlotFailed(this.slotId);

  final String slotId;

  @override
  List<Object?> get props => [slotId];
}

// slots only leave the feed while it is at rest, never under a finger
final class FeedScrollChanged extends ReelsEvent {
  const FeedScrollChanged({required this.scrolling});

  final bool scrolling;

  @override
  List<Object?> get props => [scrolling];
}
