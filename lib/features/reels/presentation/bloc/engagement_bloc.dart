import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';

part 'engagement_event.dart';
part 'engagement_state.dart';

// what the viewer has liked and who they follow, for this visit
class EngagementBloc extends BaseBloc<EngagementEvent, EngagementState> {
  EngagementBloc() : super(const EngagementState()) {
    on<ReelLikeToggled>(_likeToggled);
    on<ReelDoubleTapped>(_doubleTapped);
    on<CreatorFollowToggled>(_followToggled);
  }

  void _likeToggled(ReelLikeToggled event, Emitter<EngagementState> emit) {
    final liked = Set.of(state.liked);
    if (!liked.remove(event.reelId)) liked.add(event.reelId);
    emit(state.copyWith(liked: liked));
  }

  void _doubleTapped(ReelDoubleTapped event, Emitter<EngagementState> emit) {
    if (state.liked.contains(event.reelId)) return;
    emit(state.copyWith(liked: {...state.liked, event.reelId}));
  }

  void _followToggled(
    CreatorFollowToggled event,
    Emitter<EngagementState> emit,
  ) {
    final following = Set.of(state.following);
    if (!following.remove(event.handle)) following.add(event.handle);
    emit(state.copyWith(following: following));
  }
}
