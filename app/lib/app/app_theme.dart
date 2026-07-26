import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const primary = Color(0xFF5B6CF6);
  static const primaryDark = Color(0xFF17213B);
  static const primarySoft = Color(0xFFEFF2FF);
  static const background = Color(0xFFF5F7FB);
  static const card = Colors.white;
  static const text = Color(0xFF121A2F);
  static const muted = Color(0xFF7A8397);
  static const border = Color(0xFFE7EBF3);
  static const success = Color(0xFF25C184);
  static const successSoft = Color(0xFFE8FFF5);
  static const warning = Color(0xFFF4A62A);
  static const warningSoft = Color(0xFFFFF5DF);
  static const danger = Color(0xFFFF5B73);
  static const dangerSoft = Color(0xFFFFEEF2);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.card,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
