import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

abstract final class AppTextStyles {
  static TextStyle get display => GoogleFonts.sora(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: AppColors.textPrimary,
      );

  static TextStyle get heading => GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get handle => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.sora(
        fontSize: 13.5,
        height: 1.45,
        color: AppColors.textPrimary,
      );

  static TextStyle get muted => GoogleFonts.sora(
        fontSize: 13,
        height: 1.5,
        color: AppColors.textMuted,
      );

  static TextStyle get count => GoogleFonts.sora(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get cta => GoogleFonts.sora(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      );

  static TextStyle get wordmark => GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: AppColors.lime,
      );

  // retro "no signal" screen
  static const TextStyle signalHeading = TextStyle(
    fontFamily: 'monospace',
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.5,
  );

  static const TextStyle signalBody = TextStyle(
    fontSize: 14.5,
    height: 1.5,
    color: Color(0xADFFFFFF),
  );

  static const TextStyle signalButton = TextStyle(
    fontFamily: 'monospace',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 4,
    color: Colors.white,
  );
}
