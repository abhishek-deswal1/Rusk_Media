import 'dart:io';

import 'package:flutter/services.dart';
import 'package:rusk_media/core/logger/app_logger.dart';

// the phone's own media volume, so the hold gesture moves the same level the
// hardware keys do. anything that can't reach the platform returns null and
// the pool keeps using the app's own volume instead
class SystemVolumeService {
  const SystemVolumeService();

  static const String channelName = 'system_volume';
  static const String changesChannelName = 'system_volume/changes';
  static const MethodChannel _channel = MethodChannel(channelName);
  static const EventChannel _changes = EventChannel(changesChannelName);

  // 0..1, or null when there is no system volume to follow
  Future<double?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<double>('get');
    } on MissingPluginException {
      return null;
    } on Object catch (e) {
      AppLogger.logWarning('system volume read failed: $e');
      return null;
    }
  }

  // the level the phone actually took, or null if it refused (do not
  // disturb) or can't be reached
  Future<double?> set(double level) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<double>('set', level);
    } on MissingPluginException {
      return null;
    } on Object catch (e) {
      AppLogger.logWarning('system volume set failed: $e');
      return null;
    }
  }

  // the hardware keys, or another app, moving the volume while we are open
  Stream<double> get changes {
    if (!Platform.isAndroid) return const Stream.empty();
    return _changes
        .receiveBroadcastStream()
        .where((level) => level is num)
        .map((level) => (level as num).toDouble())
        .handleError(
          (Object e) => AppLogger.logWarning('system volume stream: $e'),
        );
  }
}
