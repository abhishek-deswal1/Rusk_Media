import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rusk_media/features/reels/domain/usecases/tips.dart';
import 'package:rusk_media/features/reels/presentation/bloc/onboarding_bloc.dart';

class _MockShouldShowTips extends Mock implements ShouldShowTips {}

class _MockMarkTipsSeen extends Mock implements MarkTipsSeen {}

void main() {
  late _MockShouldShowTips shouldShowTips;
  late _MockMarkTipsSeen markTipsSeen;

  OnboardingBloc build() => OnboardingBloc(
        shouldShowTips: shouldShowTips,
        markTipsSeen: markTipsSeen,
      );

  setUp(() {
    shouldShowTips = _MockShouldShowTips();
    markTipsSeen = _MockMarkTipsSeen();
    when(() => shouldShowTips()).thenReturn(true);
    when(() => markTipsSeen()).thenAnswer((_) async {});
  });

  test('a first run starts with the tips pending', () {
    expect(build().state, const OnboardingState(tipsPending: true));
  });

  test('a returning viewer gets neither the tips nor the swipe hint', () {
    when(() => shouldShowTips()).thenReturn(false);
    expect(build().state, const OnboardingState());
  });

  blocTest<OnboardingBloc, OnboardingState>(
    'closing tips stores it once and arms the swipe hint',
    build: build,
    act: (bloc) => bloc
      ..add(const TipsClosed())
      ..add(const TipsClosed()),
    expect: () => const [OnboardingState(swipeHintArmed: true)],
    verify: (_) => verify(() => markTipsSeen()).called(1),
  );

  blocTest<OnboardingBloc, OnboardingState>(
    'the swipe hint is disarmed once it has played',
    build: build,
    seed: () => const OnboardingState(swipeHintArmed: true),
    act: (bloc) => bloc
      ..add(const SwipeHintPlayed())
      ..add(const SwipeHintPlayed()),
    expect: () => const [OnboardingState()],
  );

  blocTest<OnboardingBloc, OnboardingState>(
    'moving to another reel disarms the swipe hint',
    build: build,
    seed: () => const OnboardingState(swipeHintArmed: true),
    act: (bloc) => bloc.add(const ReelMovedOn()),
    expect: () => const [OnboardingState()],
  );

  blocTest<OnboardingBloc, OnboardingState>(
    'moving on before the tips are closed leaves them up',
    build: build,
    act: (bloc) => bloc.add(const ReelMovedOn()),
    expect: () => <OnboardingState>[],
  );
}
