import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';
import 'package:rusk_media/features/reels/domain/usecases/tips.dart';

part 'onboarding_event.dart';
part 'onboarding_state.dart';

// first-run help: the tips sheet, then the gesture guide once it is closed
class OnboardingBloc extends BaseBloc<OnboardingEvent, OnboardingState> {
  OnboardingBloc({
    required ShouldShowTips shouldShowTips,
    required MarkTipsSeen markTipsSeen,
  })  : _markTipsSeen = markTipsSeen,
        super(OnboardingState(tipsPending: shouldShowTips())) {
    on<TipsClosed>(_tipsClosed);
    on<SwipeHintPlayed>(_swipeHintPlayed);
    on<ReelMovedOn>(_movedOn);
  }

  final MarkTipsSeen _markTipsSeen;

  Future<void> _tipsClosed(
    TipsClosed event,
    Emitter<OnboardingState> emit,
  ) async {
    if (!state.tipsPending) return;
    emit(state.copyWith(tipsPending: false, swipeHintArmed: true));
    await _markTipsSeen();
  }

  void _swipeHintPlayed(
    SwipeHintPlayed event,
    Emitter<OnboardingState> emit,
  ) {
    if (!state.swipeHintArmed) return;
    emit(state.copyWith(swipeHintArmed: false));
  }

  // moving on by themselves means the swipe hint has nothing left to teach
  void _movedOn(ReelMovedOn event, Emitter<OnboardingState> emit) {
    if (!state.swipeHintArmed) return;
    emit(state.copyWith(swipeHintArmed: false));
  }
}
