import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// import 'features/shell/app_shell.dart';
import 'features/auth_example.dart';
import 'features/welcome/welcome_page.dart';
import 'theme/app_theme.dart';
import 'widgets/adaptive_status_bar.dart';
import 'widgets/smooth_scroll_behavior.dart';

// Key para capturar una instantánea del árbol de widgets principal
final GlobalKey appRepaintBoundaryKey = GlobalKey();

// Última instantánea capturada (opcional) usada como fallback durante transiciones
Uint8List? lastAppSnapshot;

/// Captura la instantánea en background y la almacena en `lastAppSnapshot`.
void captureAndStoreAppSnapshot() {
  captureAppSnapshot().then((bytes) {
    if (bytes != null) lastAppSnapshot = bytes;
  });
}

/// Captura una imagen PNG del estado actual de la app (si está disponible).
Future<Uint8List?> captureAppSnapshot() async {
  try {
    final boundary = appRepaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // Para evitar imágenes de instantánea excesivamente grandes (que causan
    // decodificación lenta y jank en transiciones), limitamos el pixelRatio
    // en web y en dispositivos con alta densidad.
    final double pixelRatio = kIsWeb ? 1.0 : math.min(1.5, ui.window.devicePixelRatio);
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

class GymCoachApp extends StatelessWidget {
  const GymCoachApp({super.key, required this.showWelcome});

  final bool showWelcome;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePrefs>(
      valueListenable: appThemePrefsNotifier,
      builder: (context, prefs, _) {
        final accent = prefs.accent.color;
        return MaterialApp(
          title: 'CanaryCoach',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const SmoothScrollBehavior(),
          theme: AppTheme.light(accent: accent),
          darkTheme: AppTheme.dark(accent: accent),
          themeMode: prefs.mode,
          color: const Color(0xFF0D0D0D),
          // Wrap all routes/screens so the status bar adopte el color
          // adecuado automáticamente. Para pantallas con fondo complejo
          // (gradiente/imagen) pueden pasar `statusBarColor` explícito
          // mediante un widget `AdaptiveStatusBar` local si necesitan más
          // control.
          builder: (context, child) => AdaptiveStatusBar(
            child: child ?? const SizedBox.shrink(),
          ),
          home: RepaintBoundary(
            key: appRepaintBoundaryKey,
            child: showWelcome ? const WelcomePage() : const AuthExamplePage(),
          ),
        );
      },
    );
  }
}