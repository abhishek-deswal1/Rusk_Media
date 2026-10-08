part of 'paywall_bloc.dart';

class PaywallState extends BaseState {
  const PaywallState({this.unlocked = false});

  static const EpisodePaywall policy = EpisodePaywall();

  // for this session only; a fresh launch locks again
  final bool unlocked;

  int? lockedIndex(int loaded) => unlocked ? null : policy.lockedIndex(loaded);

  // the feed can't scroll past this page while it is set
  int? lockedPage(List<FeedItem> items) =>
      unlocked ? null : policy.lockedPage(items);

  bool canPlay(int episodeIndex) => unlocked || !policy.locks(episodeIndex);

  // derived rather than stored, so coming back to the episode shows it again
  bool showsOn(int episodeIndex) =>
      !unlocked && policy.isLockedEpisode(episodeIndex);

  PaywallState copyWith({bool? unlocked}) {
    return PaywallState(unlocked: unlocked ?? this.unlocked);
  }

  @override
  List<Object?> get props => [unlocked];
}
