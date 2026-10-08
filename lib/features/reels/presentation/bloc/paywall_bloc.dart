import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rusk_media/core/base/base_bloc.dart';
import 'package:rusk_media/features/reels/domain/entities/feed_item.dart';
import 'package:rusk_media/features/reels/domain/policies/episode_paywall.dart';

part 'paywall_event.dart';
part 'paywall_state.dart';

// whether the viewer has unlocked; where the lock sits is read against the
// feed through the state's helpers
class PaywallBloc extends BaseBloc<PaywallEvent, PaywallState> {
  PaywallBloc() : super(const PaywallState()) {
    on<PaywallUnlocked>(_unlocked);
  }

  void _unlocked(PaywallUnlocked event, Emitter<PaywallState> emit) {
    if (state.unlocked) return;
    emit(state.copyWith(unlocked: true));
  }
}
