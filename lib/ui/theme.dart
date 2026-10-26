import 'package:material_ui/material_ui.dart';

abstract final class AppColors {
  static const primary = Color(0xFF5C73F2);
  static const ink = Color(0xFF202741);
  static const muted = Color(0xFF8B91A8);
  static const mint = Color(0xFF43BFAC);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    surface: const Color(0xFFF7F8FC),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    hoverColor: AppColors.primary.withValues(alpha: .04),
    focusColor: AppColors.primary.withValues(alpha: .07),
    highlightColor: AppColors.primary.withValues(alpha: .06),
    splashColor: AppColors.primary.withValues(alpha: .08),
    fontFamily: 'sans-serif',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
        letterSpacing: -1,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: AppColors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontFamily: 'sans-serif',
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.muted.withValues(alpha: .1),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .68),
      hintStyle: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.normal,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        textStyle: const TextStyle(
          fontFamily: 'sans-serif',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.ink),
    ),
    // 弹出菜单位于 Navigator overlay 中，需要单独配置，不能继承页面的玻璃卡片。
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xF5F8FAFF),
      surfaceTintColor: Colors.transparent,
      elevation: 5,
      shadowColor: AppColors.ink.withValues(alpha: .1),
      position: PopupMenuPosition.under,
      menuPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white, width: 1),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'sans-serif',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.disabled)
              ? AppColors.muted
              : AppColors.ink,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 3),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontFamily: 'sans-serif',
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
