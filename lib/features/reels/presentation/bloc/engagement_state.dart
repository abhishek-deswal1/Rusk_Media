part of 'engagement_bloc.dart';

class EngagementState extends BaseState {
  const EngagementState({
    this.liked = const {},
    this.following = const {},
  });

  final Set<String> liked;
  final Set<String> following;

  EngagementState copyWith({
    Set<String>? liked,
    Set<String>? following,
  }) {
    return EngagementState(
      liked: liked ?? this.liked,
      following: following ?? this.following,
    );
  }

  @override
  List<Object?> get props => [liked, following];
}
