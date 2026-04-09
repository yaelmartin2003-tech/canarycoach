import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// ScrollBehavior que favorece un desplazamiento más natural y elimina el
/// efecto de glow para una experiencia más fluida en todas las plataformas.
class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Usar física nativa por plataforma para evitar rigidez:
    // - iOS/macOS: Bouncing
    // - Android/Fuchsia/Windows/Linux: Clamping
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Suprimir el glow/overscroll indicator para que el scroll se sienta más "limpio".
    return child;
  }
}
