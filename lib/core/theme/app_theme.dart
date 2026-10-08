import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rusk_media/core/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.ink,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.lime,
        secondary: AppColors.teal,
        surface: AppColors.inkRaised,
      ),
      textTheme: GoogleFonts.soraTextTheme(base.textTheme),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.inkRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
