import 'package:google_mobile_ads/google_mobile_ads.dart';

// idle -> loading -> loaded | failed
sealed class AdSlotState {
  const AdSlotState();
}

final class AdSlotIdle extends AdSlotState {
  const AdSlotIdle();
}

final class AdSlotLoading extends AdSlotState {
  const AdSlotLoading();
}

final class AdSlotLoaded extends AdSlotState {
  const AdSlotLoaded(this.ad);

  final NativeAd ad;
}

final class AdSlotFailed extends AdSlotState {
  const AdSlotFailed(this.reason);

  final String reason;
}
