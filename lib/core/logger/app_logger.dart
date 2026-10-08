import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  static void logError(String message, [Object? error, StackTrace? stack]) {
    if (kReleaseMode) return;
    developer.log(
      message,
      name: 'ERROR',
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  static void logWarning(String message) => _flat('WARN', 900, message);

  static void logInfo(String message) => _flat('INFO', 800, message);

  static void logDebug(String message) => _flat('DEBUG', 500, message);

  static void _flat(String name, int level, String message) {
    if (kReleaseMode) return;
    developer.log(message, name: name, level: level);
  }
}
