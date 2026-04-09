import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const background = Color(0xFF0D0D0D);
  static const card = Color(0xFF1C1C1E);
  static const text = Color(0xFFFFFFFF);
  static const secondaryText = Color(0xFFA1A1A1);
  static const accent = Color(0xFFFF9800);
  static const navBackground = Color(0xFF111111);
  static const navBorder = Color(0xFF222222);
}

enum AppAccentOption { orange, yellow, red, blue }

extension AppAccentOptionX on AppAccentOption {
  String get label {
    switch (this) {
      case AppAccentOption.orange:
        return 'Naranja';
      case AppAccentOption.yellow:
        return 'Amarillo';
      case AppAccentOption.red:
        return 'Rojo';
      case AppAccentOption.blue:
        return 'Azul';
    }
  }

  Color get color {
    switch (this) {
      case AppAccentOption.orange:
        return const Color(0xFFFF9800);
      case AppAccentOption.yellow:
        return const Color(0xFFFFC107);
      case AppAccentOption.red:
        return const Color(0xFFE53935);
      case AppAccentOption.blue:
        return const Color(0xFF1E88E5);
    }
  }
}

class AppThemePrefs {
  const AppThemePrefs({
    required this.mode,
    required this.accent,
  });

  final ThemeMode mode;
  final AppAccentOption accent;

  AppThemePrefs copyWith({
    ThemeMode? mode,
    AppAccentOption? accent,
  }) {
    return AppThemePrefs(
      mode: mode ?? this.mode,
      accent: accent ?? this.accent,
    );
  }
}

final ValueNotifier<AppThemePrefs> appThemePrefsNotifier =
    ValueNotifier(const AppThemePrefs(
      mode: ThemeMode.dark,
      accent: AppAccentOption.orange,
    ));

const _themeModeKey = 'theme_mode';
const _themeAccentKey = 'theme_accent';

ThemeMode _modeFromString(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.dark;
  }
}

String _modeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

AppAccentOption _accentFromString(String? raw) {
  switch (raw) {
    case 'yellow':
      return AppAccentOption.yellow;
    case 'red':
      return AppAccentOption.red;
    case 'blue':
      return AppAccentOption.blue;
    case 'orange':
    default:
      return AppAccentOption.orange;
  }
}

String _accentToString(AppAccentOption accent) {
  switch (accent) {
    case AppAccentOption.orange:
      return 'orange';
    case AppAccentOption.yellow:
      return 'yellow';
    case AppAccentOption.red:
      return 'red';
    case AppAccentOption.blue:
      return 'blue';
  }
}

Future<void> loadAppThemePrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final mode = _modeFromString(prefs.getString(_themeModeKey));
  final accent = _accentFromString(prefs.getString(_themeAccentKey));
  appThemePrefsNotifier.value = AppThemePrefs(mode: mode, accent: accent);
}

Future<void> setAppThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  appThemePrefsNotifier.value = appThemePrefsNotifier.value.copyWith(mode: mode);
  await prefs.setString(_themeModeKey, _modeToString(mode));
}

Future<void> setAppAccent(AppAccentOption accent) async {
  final prefs = await SharedPreferences.getInstance();
  appThemePrefsNotifier.value = appThemePrefsNotifier.value.copyWith(
    accent: accent,
  );
  await prefs.setString(_themeAccentKey, _accentToString(accent));
}

class AppTheme {
  // Page background (light mode)
  static const lightPageBackground = Color(0xFFF7F7F8);
  // Modal surface (white) in light mode
  static const lightModalSurface = Color(0xFFFFFFFF);
  static const lightModalBorder = Colors.transparent;
  static const lightSurfaceBorder = Color(0xFFA6ADB5);

  static Color modalSurfaceFor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : lightModalSurface;
  }

  static Color pageBackgroundFor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.scaffoldBackgroundColor
        : lightPageBackground;
  }

  static Color modalBorderFor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.dividerColor
        : lightModalBorder;
  }

  static Color surfaceBorderFor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.dividerColor
        : lightSurfaceBorder;
  }

  static List<BoxShadow>? surfaceShadowFor(
    BuildContext context, {
    double alpha = 0.10,
    double blurRadius = 14,
    double offsetY = 4,
    bool addTopHighlight = false,
  }) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return null;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: alpha),
        blurRadius: blurRadius,
        offset: Offset(0, offsetY),
      ),
      if (addTopHighlight)
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.36),
          blurRadius: 0,
          spreadRadius: -1,
          offset: const Offset(0, 1),
        ),
    ];
  }

  static List<BoxShadow>? modalShadowFor(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return null;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static ThemeData dark({required Color accent}) {
    final colorScheme = ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: AppColors.card,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.text,
      surfaceTint: Colors.transparent,
      primaryContainer: Color(0xFF3D1F00),
      onPrimaryContainer: accent,
    );

    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      splashColor: accent.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.text,
        centerTitle: false,
      ),
      cardColor: AppColors.card,
      dividerColor: AppColors.navBorder,
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(color: AppColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.navBackground,
        selectedItemColor: accent,
        unselectedItemColor: AppColors.secondaryText,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  static ThemeData light({required Color accent}) {
    final base = ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme.light(
      primary: accent,
      secondary: accent,
      surface: const Color(0xFFF1F2F4),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: const Color(0xFF121212),
      surfaceTint: Colors.transparent,
      primaryContainer: accent.withValues(alpha: 0.15),
      onPrimaryContainer: accent,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F7F8),
      splashColor: accent.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: const Color(0xFF121212),
        displayColor: const Color(0xFF121212),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F7F8),
        elevation: 0,
        foregroundColor: Color(0xFF121212),
        centerTitle: false,
      ),
      cardColor: const Color(0xFFF6F7F9),
      dividerColor: lightSurfaceBorder,
      dialogTheme: const DialogThemeData(
        backgroundColor: lightModalSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Color.fromRGBO(0, 0, 0, 0.06),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightModalSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Color.fromRGBO(0, 0, 0, 0.06),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: lightModalSurface,
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(color: Color(0xFF121212)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFFF1F2F4),
        selectedItemColor: accent,
        unselectedItemColor: const Color(0xFF767676),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}