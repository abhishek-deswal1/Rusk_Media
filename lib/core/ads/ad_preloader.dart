import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:rusk_media/core/ads/ad_config.dart';
import 'package:rusk_media/core/ads/ad_slot_state.dart';
import 'package:rusk_media/core/logger/app_logger.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

typedef NativeAdBuilder = NativeAd Function(
  String slotId,
  NativeAdListener listener,
);

// the ad side of the video pool: loads each slot's native ad before the
// viewer gets there, so swiping into an ad is as quick as into a video.
// it owns every ad it creates and disposes all of them
class AdPreloader {
  AdPreloader({
    NativeAdBuilder? createAd,
    this.loadTimeout = AdConfig.loadTimeout,
  }) : _createAd = createAd ?? _gamNative;

  final NativeAdBuilder _createAd;
  final Duration loadTimeout;

  final Map<String, ValueNotifier<AdSlotState>> _states = {};
  final Map<String, NativeAd> _pending = {};
  final Map<String, Timer> _timeouts = {};
  final StreamController<String> _failures = StreamController.broadcast();
  bool _disposed = false;

  // slot ids that errored, came back empty or timed out
  Stream<String> get failures => _failures.stream;

  ValueListenable<AdSlotState> stateOf(String slotId) => _notifier(slotId);

  // starts any of these that haven't started yet
  void load(Iterable<String> slotIds) {
    if (_disposed) return;
    slotIds.forEach(_load);
  }

  // the slot left the feed
  void release(String slotId) {
    if (_disposed) return;
    _timeouts.remove(slotId)?.cancel();
    unawaited(_pending.remove(slotId)?.dispose());
    final notifier = _states[slotId];
    if (notifier == null) return;
    if (notifier.value case AdSlotLoaded(:final ad)) unawaited(ad.dispose());
    // the notifier stays until dispose: a page leaving this frame may still
    // be listening to it
    notifier.value = const AdSlotFailed('released');
  }

  void dispose() {
    _disposed = true;
    for (final timer in _timeouts.values) {
      timer.cancel();
    }
    _timeouts.clear();
    for (final ad in _pending.values) {
      unawaited(ad.dispose());
    }
    _pending.clear();
    for (final notifier in _states.values) {
      if (notifier.value case AdSlotLoaded(:final ad)) unawaited(ad.dispose());
      notifier.dispose();
    }
    _states.clear();
    unawaited(_failures.close());
  }

  ValueNotifier<AdSlotState> _notifier(String slotId) =>
      _states.putIfAbsent(slotId, () => ValueNotifier(const AdSlotIdle()));

  void _load(String slotId) {
    final notifier = _notifier(slotId);
    if (notifier.value is! AdSlotIdle) return;
    notifier.value = const AdSlotLoading();

    late final NativeAd ad;
    ad = _createAd(
      slotId,
      NativeAdListener(
        onAdLoaded: (_) {
          // a late answer for a load that already timed out or was released
          if (_disposed || !identical(_pending[slotId], ad)) return;
          _pending.remove(slotId);
          _timeouts.remove(slotId)?.cancel();
          notifier.value = AdSlotLoaded(ad);
          AppLogger.logDebug('ads $slotId loaded');
        },
        onAdFailedToLoad: (_, error) {
          if (_disposed || !identical(_pending[slotId], ad)) return;
          _fail(slotId, 'code ${error.code}: ${error.message}');
        },
      ),
    );
    _pending[slotId] = ad;
    _timeouts[slotId] = Timer(loadTimeout, () => _fail(slotId, 'timeout'));
    AppLogger.logDebug('ads $slotId loading');
    unawaited(ad.load());
  }

  void _fail(String slotId, String reason) {
    if (_disposed) return;
    _timeouts.remove(slotId)?.cancel();
    unawaited(_pending.remove(slotId)?.dispose());
    _notifier(slotId).value = AdSlotFailed(reason);
    AppLogger.logDebug('ads $slotId failed ($reason)');
    _failures.add(slotId);
  }

  static NativeAd _gamNative(String slotId, NativeAdListener listener) =>
      NativeAd.fromAdManagerRequest(
        adUnitId: AdConfig.unitFor(slotId),
        adManagerRequest: const AdManagerAdRequest(),
        // a video creative starts silent, like the feed around it expects
        nativeAdOptions: NativeAdOptions(
          videoOptions: VideoOptions(startMuted: true),
        ),
        nativeTemplateStyle: _template,
        listener: listener,
      );

  // dark template in the player's colours
  static final NativeTemplateStyle _template = NativeTemplateStyle(
    templateType: TemplateType.medium,
    mainBackgroundColor: AppColors.inkRaised,
    cornerRadius: 18,
    callToActionTextStyle: NativeTemplateTextStyle(
      textColor: AppColors.ink,
      backgroundColor: AppColors.lime,
      style: NativeTemplateFontStyle.bold,
      size: 16,
    ),
    primaryTextStyle: NativeTemplateTextStyle(
      textColor: AppColors.textPrimary,
      style: NativeTemplateFontStyle.bold,
      size: 16,
    ),
    secondaryTextStyle: NativeTemplateTextStyle(
      textColor: AppColors.textMuted,
      size: 14,
    ),
    tertiaryTextStyle: NativeTemplateTextStyle(
      textColor: AppColors.textMuted,
      size: 13,
    ),
  );
}
