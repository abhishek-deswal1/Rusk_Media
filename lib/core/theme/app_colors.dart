import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color ink = Color(0xFF0D0F14);
  static const Color inkRaised = Color(0xFF171A22);
  static const Color inkLine = Color(0x1FFFFFFF);
  static const Color glass = Color(0x59000000);

  static const Color lime = Color(0xFFC8F560);
  static const Color teal = Color(0xFF3DDBC4);
  static const Color rose = Color(0xFFFF5A87);

  static const Color textPrimary = Colors.white;
  static const Color textMuted = Color(0xB3FFFFFF);

  static const LinearGradient limeToTeal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lime, teal],
  );

  // retro "no signal" screen keeps its own look
  static const Color signalBase = Color(0xFF141417);
  static const Color signalRaised = Color(0xFF1B1B20);
  static const Color signalGreen = Color(0xFF7CF29C);
  static const Color signalCyan = Color(0xFF00E5FF);
  static const Color signalRed = Color(0xFFFF4A2E);
  static const Color signalMagenta = Color(0xFFFF3B47);
}
