import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'widgets/motion.dart';

class AppColors {
  static const greenDeep = Color(0xFF08251E);
  static const green900 = Color(0xFF0B2A22);
  static const green800 = Color(0xFF123C32);
  static const green700 = Color(0xFF1A4A3E);
  static const green600 = Color(0xFF2B6555);
  static const gold400 = Color(0xFFDCC58E);
  static const gold500 = Color(0xFFC8A96B);
  static const gold600 = Color(0xFFB3934F);
  static const gold700 = Color(0xFF8A6F35);
  static const slate50 = Color(0xFFF8F5EE);
  static const slate100 = Color(0xFFEFEDE4);
  static const slate200 = Color(0xFFE0DED3);
  static const slate300 = Color(0xFFC5CFC2);
  static const slate400 = Color(0xFF69726A);
  static const slate500 = Color(0xFF4A544B);
  static const slate600 = Color(0xFF333B33);
  static const emerald = Color(0xFF2F7D5B);
  static const emeraldBg = Color(0xFFD9EEDF);
  static const amber = Color(0xFF7A5C1E);
  static const amberBg = Color(0xFFF6EBCF);
  static const red = Color(0xFF991B1B);
  static const redBg = Color(0xFFFEE2E2);
  static const blue = Color(0xFF1A4A3E);
  static const blueBg = Color(0xFFDFE8DA);
}

const goldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.gold400, AppColors.gold600],
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold500,
    brightness: Brightness.light,
    primary: AppColors.green800,
    secondary: AppColors.gold500,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // One typeface for the whole app; numbers use even-width digits so
    // amounts line up and don't jitter while counting.
    fontFamily: 'PlusJakartaSans',
    scaffoldBackgroundColor: AppColors.green800,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SmoothPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: SmoothPageTransitionsBuilder(),
      TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
      TargetPlatform.linux: SmoothPageTransitionsBuilder(),
    }),
    splashFactory: InkSparkle.splashFactory,
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.green800),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gold500,
      linearTrackColor: AppColors.slate100,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.green900 : AppColors.slate400),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.gold500 : AppColors.slate100),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: AppColors.green900, borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(color: AppColors.gold400, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.slate50,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.slate400),
      border: border(AppColors.slate200),
      enabledBorder: border(AppColors.slate200),
      focusedBorder: border(AppColors.gold500, 2),
      errorBorder: border(AppColors.red),
      focusedErrorBorder: border(AppColors.red, 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.green900,
      contentTextStyle: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gold500),
      ),
    ),
  );
}
