part of 'engagement_bloc.dart';

sealed class EngagementEvent extends BaseEvent {
  const EngagementEvent();
}

final class ReelLikeToggled extends EngagementEvent {
  const ReelLikeToggled(this.reelId);

  final String reelId;

  @override
  List<Object?> get props => [reelId];
}

// a double tap only ever adds a like
final class ReelDoubleTapped extends EngagementEvent {
  const ReelDoubleTapped(this.reelId);

  final String reelId;

  @override
  List<Object?> get props => [reelId];
}

final class CreatorFollowToggled extends EngagementEvent {
  const CreatorFollowToggled(this.handle);

  final String handle;

  @override
  List<Object?> get props => [handle];
}
