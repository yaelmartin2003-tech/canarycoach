import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Envuelve una pantalla y aplica un [SystemUiOverlayStyle] adaptado al
/// color de fondo indicado (o a `Theme.of(context).scaffoldBackgroundColor`).
///
/// Uso:
/// ```dart
/// AdaptiveStatusBar(
///   child: Scaffold(...),
/// )
/// ```
class AdaptiveStatusBar extends StatelessWidget {
  const AdaptiveStatusBar({
    Key? key,
    required this.child,
    this.statusBarColor,
    this.iconBrightness,
  }) : super(key: key);

  final Widget child;

  /// Color que se quiere usar en la barra de estado. Si es null se usa
  /// `Theme.of(context).scaffoldBackgroundColor`.
  final Color? statusBarColor;

  /// Forzar brillo de iconos en la barra (opcional). Si es null se calcula
  /// a partir de la luminancia del color.
  final Brightness? iconBrightness;

  @override
  Widget build(BuildContext context) {
    final Color base = statusBarColor ?? Theme.of(context).scaffoldBackgroundColor;

    // Elegimos brillo de iconos según luminancia si no se fuerza.
    final Brightness icons = iconBrightness ?? (base.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light);

    // Para iOS, statusBarBrightness indica el brillo del contenido bajo la barra.
    final Brightness iosBrightness = icons == Brightness.dark ? Brightness.light : Brightness.dark;

    final overlay = SystemUiOverlayStyle(
      statusBarColor: base,
      statusBarIconBrightness: icons,
      statusBarBrightness: iosBrightness,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: child,
    );
  }
}
