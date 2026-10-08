part of 'paywall_bloc.dart';

sealed class PaywallEvent extends BaseEvent {
  const PaywallEvent();
}

final class PaywallUnlocked extends PaywallEvent {
  const PaywallUnlocked();
}
