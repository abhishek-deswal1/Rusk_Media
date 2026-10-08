part of 'onboarding_bloc.dart';

sealed class OnboardingEvent extends BaseEvent {
  const OnboardingEvent();
}

final class TipsClosed extends OnboardingEvent {
  const TipsClosed();
}

final class SwipeHintPlayed extends OnboardingEvent {
  const SwipeHintPlayed();
}

// the viewer went to another reel, or onto an ad
final class ReelMovedOn extends OnboardingEvent {
  const ReelMovedOn();
}
