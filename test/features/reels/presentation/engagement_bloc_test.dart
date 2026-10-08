import 'package:bloc_test/bloc_test.dart';
import 'package:rusk_media/features/reels/presentation/bloc/engagement_bloc.dart';

void main() {
  blocTest<EngagementBloc, EngagementState>(
    'like toggles, double tap only adds',
    build: EngagementBloc.new,
    act: (bloc) => bloc
      ..add(const ReelDoubleTapped('a'))
      ..add(const ReelDoubleTapped('a'))
      ..add(const ReelLikeToggled('a')),
    expect: () => const [
      EngagementState(liked: {'a'}),
      EngagementState(),
    ],
  );

  blocTest<EngagementBloc, EngagementState>(
    'likes are kept per reel',
    build: EngagementBloc.new,
    act: (bloc) => bloc
      ..add(const ReelLikeToggled('a'))
      ..add(const ReelDoubleTapped('b'))
      ..add(const ReelLikeToggled('a')),
    expect: () => const [
      EngagementState(liked: {'a'}),
      EngagementState(liked: {'a', 'b'}),
      EngagementState(liked: {'b'}),
    ],
  );

  blocTest<EngagementBloc, EngagementState>(
    'follow toggles per handle',
    build: EngagementBloc.new,
    act: (bloc) => bloc
      ..add(const CreatorFollowToggled('h_a'))
      ..add(const CreatorFollowToggled('h_b'))
      ..add(const CreatorFollowToggled('h_a')),
    expect: () => const [
      EngagementState(following: {'h_a'}),
      EngagementState(following: {'h_a', 'h_b'}),
      EngagementState(following: {'h_b'}),
    ],
  );
}
