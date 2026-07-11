import 'package:flutter/material.dart';

class AppColors {
  static const coreNavy = Color(0xFF1E2849);
  static const clubPrimary = Color(0xFF195534);
  static const clubPrimaryHover = Color(0xFF216B42);
  static const clubDark = Color(0xFF0F3922);
  static const clubLight = Color(0xFF2F8A55);
  static const clubCardNavy = Color(0xFF162C48);
  static const clubCardNavyLight = Color(0xFF203B5D);
  static const clubLightText = Color(0xFFE3E7E8);
  static const clubDivider = Color(0xFF39506A);
  static const secondaryBurgundy = Color(0xFF8A2F4F);
  static const topBanner = clubCardNavy;
  static const gold = Color(0xFFF6C834);
  static const offWhite = Color(0xFFC7CBCC);

  static const navy = coreNavy;
  static const navyDark = clubDark;
  static const clubGreen = clubPrimary;
  static const clubGreenDark = clubDark;
  static const clubGreenLight = clubLight;

  static const bg = clubCardNavy;
  static const surface = clubCardNavy;
  static const text = clubLightText;
  static const muted = offWhite;
  static const successBg = Color(0xFF173D2A);
  static const success = clubPrimary;
  static const dangerBg = Color(0xFF4A1E2E);
  static const danger = Color(0xFFFFB7C8);

  static const clubBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F3922), Color(0xFF195534), Color(0xFF2E7A4F)],
    stops: [0.0, 0.55, 1.0],
  );
}

class AppRadius {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

class AppTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.clubLight,
      brightness: Brightness.dark,
      primary: AppColors.clubLight,
      onPrimary: AppColors.clubLightText,
      primaryContainer: AppColors.clubCardNavyLight,
      onPrimaryContainer: AppColors.clubLightText,
      secondary: AppColors.secondaryBurgundy,
      onSecondary: AppColors.clubLightText,
      secondaryContainer: AppColors.clubCardNavyLight,
      onSecondaryContainer: AppColors.clubLightText,
      tertiary: AppColors.gold,
      onTertiary: AppColors.coreNavy,
      error: AppColors.secondaryBurgundy,
      errorContainer: AppColors.dangerBg,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.offWhite,
      outline: AppColors.clubLight,
      outlineVariant: AppColors.clubDivider,
      surfaceContainer: AppColors.clubCardNavy,
      surfaceContainerHighest: AppColors.clubCardNavyLight,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
    );

    return base.copyWith(
      canvasColor: AppColors.clubCardNavyLight,
      disabledColor: AppColors.offWhite.withValues(alpha: 0.48),
      scaffoldBackgroundColor: Colors.transparent,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.offWhite),
        trackColor: WidgetStateProperty.all(
          AppColors.clubDivider.withValues(alpha: .55),
        ),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.topBanner,
        foregroundColor: AppColors.offWhite,
        iconTheme: IconThemeData(color: AppColors.offWhite),
        actionsIconTheme: IconThemeData(color: AppColors.offWhite),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.clubCardNavy,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.clubLight),
        ),
        margin: EdgeInsets.zero,
      ),
      iconTheme: const IconThemeData(color: AppColors.clubLight),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.clubLight,
        textColor: AppColors.clubLightText,
        titleTextStyle: TextStyle(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(color: AppColors.clubLightText),
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: AppColors.offWhite,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: AppColors.clubLightText,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: AppColors.clubLightText,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          color: AppColors.clubLightText,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: AppColors.clubLightText,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: AppColors.offWhite,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.clubCardNavyLight;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.gold;
            }
            return AppColors.clubPrimary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.offWhite.withValues(alpha: 0.48);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.coreNavy;
            }
            return AppColors.offWhite;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.offWhite.withValues(alpha: 0.48);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.coreNavy;
            }
            return AppColors.offWhite;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return AppColors.coreNavy.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.coreNavy.withValues(alpha: 0.14);
            }
            return null;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            return const BorderSide(color: AppColors.gold);
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.coreNavy,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.clubLightText,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColors.clubLight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.gold),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.coreNavy,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.clubCardNavyLight,
        labelStyle: const TextStyle(color: AppColors.offWhite),
        floatingLabelStyle: const TextStyle(color: AppColors.gold),
        hintStyle: const TextStyle(color: AppColors.offWhite),
        helperStyle: const TextStyle(color: AppColors.offWhite),
        prefixIconColor: AppColors.clubLight,
        suffixIconColor: AppColors.clubLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.clubLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.clubLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.clubCardNavyLight,
        ),
        textStyle: TextStyle(color: AppColors.clubLightText),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.clubCardNavyLight),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.clubCardNavyLight,
        surfaceTintColor: Colors.transparent,
        iconColor: AppColors.clubLight,
        textStyle: TextStyle(color: AppColors.clubLightText),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.clubCardNavyLight),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.clubCardNavy,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.offWhite,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: AppColors.clubLightText),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.clubCardNavy,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.clubDivider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
