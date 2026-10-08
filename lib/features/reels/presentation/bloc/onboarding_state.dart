part of 'onboarding_bloc.dart';

class OnboardingState extends BaseState {
  const OnboardingState({
    this.tipsPending = false,
    this.swipeHintArmed = false,
  });

  // first run only; the sheet itself waits until there is a reel under it
  final bool tipsPending;

  // arms the first-run gesture guide once the tips are closed; cleared when
  // the guide has played or the viewer moves to another reel on their own
  final bool swipeHintArmed;

  OnboardingState copyWith({bool? tipsPending, bool? swipeHintArmed}) {
    return OnboardingState(
      tipsPending: tipsPending ?? this.tipsPending,
      swipeHintArmed: swipeHintArmed ?? this.swipeHintArmed,
    );
  }

  @override
  List<Object?> get props => [tipsPending, swipeHintArmed];
}
