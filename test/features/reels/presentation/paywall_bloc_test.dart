import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/entities/reel.dart';
import 'package:rusk_media/features/reels/domain/policies/feed_composer.dart';
import 'package:rusk_media/features/reels/presentation/bloc/paywall_bloc.dart';

void main() {
  // E1 E2 E3 AD E4 E5 E6 AD E7 E8: page 8 is E7
  final items = const FeedComposer().compose([
    for (var i = 0; i < 8; i++)
      Reel(
        id: 'e$i',
        handle: '',
        caption: '',
        streamUrl: 'https://x/e$i.mp4',
        avatarUrl: '',
      ),
  ]);
  const locked = PaywallState();
  const open = PaywallState(unlocked: true);

  test('episode 7 and everything after it never get a player', () {
    expect(
      [for (var i = 0; i < 8; i++) locked.canPlay(i)],
      [true, true, true, true, true, true, false, false],
    );
    expect([for (var i = 0; i < 8; i++) open.canPlay(i)], everyElement(isTrue));
  });

  test('shows on episode 7 only, and never once unlocked', () {
    expect(locked.showsOn(5), isFalse);
    expect(locked.showsOn(6), isTrue);
    expect(locked.showsOn(7), isFalse);
    expect(open.showsOn(6), isFalse);
  });

  test('the lock holds the feed on episode 7 until unlocked', () {
    expect(locked.lockedPage(items), 8);
    expect(locked.lockedIndex(items.whereType<EpisodeItem>().length), 6);
    expect(locked.lockedIndex(6), isNull);
    expect(locked.lockedIndex(7), 6);
    expect(open.lockedPage(items), isNull);
    expect(open.lockedIndex(8), isNull);
  });

  blocTest<PaywallBloc, PaywallState>(
    'unlocks once and stays unlocked for the visit',
    build: PaywallBloc.new,
    act: (bloc) => bloc
      ..add(const PaywallUnlocked())
      ..add(const PaywallUnlocked()),
    expect: () => const [open],
  );
}
