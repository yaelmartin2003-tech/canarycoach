import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/user_store.dart';
import '../../utils/shell_nav_visibility.dart';
import '../admin/admin_page.dart';
import '../chat/chat_page.dart';
import '../exercises/exercises_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precargar imágenes clave para transiciones y para evitar frames en negro
    precacheImage(const AssetImage('assets/fondo.png'), context);
    precacheImage(const AssetImage('assets/LOGO APP.png'), context);
    precacheImage(const AssetImage('assets/logo.png'), context);
    precacheImage(const AssetImage('assets/logo sin fondo CanaryCoach.png'), context);
    precacheImage(const AssetImage('assets/bienvenida 2.png'), context);
  }
  double _contentBottomInset(BuildContext context) {
    // Reserva espacio para la barra flotante (56) + separación/sombra
    // y el inset del sistema (gesture bar / notch inferior).
    return MediaQuery.viewPaddingOf(context).bottom + 76;
  }

  late final List<_ShellDestination> _baseDestinations = [
    _ShellDestination(
      label: 'Inicio',
      icon: Icons.home_rounded,
      pageBuilder: () => const HomePage(),
    ),
    _ShellDestination(
      label: 'Ejercicios',
      icon: Icons.fitness_center,
      pageBuilder: () => const ExercisesPage(),
    ),
    _ShellDestination(
      label: 'Chat',
      icon: Icons.chat_bubble_outline_rounded,
      pageBuilder: () => const ChatPage(),
    ),
    _ShellDestination(
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      pageBuilder: () => const ProfilePage(),
    ),
  ];

  late final _ShellDestination _adminDestination = _ShellDestination(
    label: 'Admin',
    icon: Icons.settings_outlined,
    pageBuilder: () => const AdminPage(),
  );

  // Cache de páginas instanciadas para mantener su estado y crear perezosamente
  final Map<int, Widget> _pageCache = {};

  List<_ShellDestination> _destinationsForRole(AppUserRole role) {
    if (role == AppUserRole.admin || role == AppUserRole.trainer) {
      return [..._baseDestinations, _adminDestination];
    }
    return _baseDestinations;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUserRole>(
      valueListenable: appUserRoleNotifier,
      builder: (context, role, _) {
        final destinations = _destinationsForRole(role);
        if (_currentIndex >= destinations.length) {
          _currentIndex = destinations.length - 1;
        }

        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final keyboardOpen = bottomInset > 0;

        // Asegurar que la página actual esté en cache para crearla perezosamente
        if (!_pageCache.containsKey(_currentIndex) || _pageCache.length > destinations.length) {
          _pageCache.removeWhere((k, v) => k >= destinations.length);
          _pageCache[_currentIndex] = destinations[_currentIndex].pageBuilder();
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/fondo.png',
                    fit: BoxFit.cover,
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: shellNavVisibleNotifier,
                        builder: (ctx, navVisible, _) {
                            // Cuando el teclado está abierto, no añadimos el padding
                            // extra de 16px para que la vista pueda quedar pegada
                            // al borde superior del teclado. Si la barra flotante está
                            // visible, dejamos el espacio necesario; si no, solo
                            // respetamos el padding del sistema (gesture bar).
                            final bottomPad = keyboardOpen
                              ? MediaQuery.viewPaddingOf(context).bottom
                              : (navVisible
                                ? _contentBottomInset(context)
                                : MediaQuery.viewPaddingOf(context).bottom);
                          // Construir un listado con widgets cacheados; páginas no creadas
                          // se representan como SizedBox.shrink() para evitar instanciarlas
                          final children = List<Widget>.generate(destinations.length, (i) {
                            final w = _pageCache[i] ?? const SizedBox.shrink();
                            return Padding(
                              padding: EdgeInsets.only(bottom: bottomPad),
                              child: w,
                            );
                          });
                          return IndexedStack(
                            index: _currentIndex,
                            children: children,
                          );
                        },
                      ),
                      if (!keyboardOpen)
                        ValueListenableBuilder<bool>(
                          valueListenable: shellNavVisibleNotifier,
                          builder: (context, visible, _) {
                            if (!visible) return const SizedBox.shrink();
                            return Positioned(
                              left: 10,
                              right: 10,
                              bottom: MediaQuery.viewPaddingOf(context).bottom + 10,
                              child: ValueListenableBuilder<int>(
                                valueListenable: chatUnreadNotifier,
                                builder: (context, unread, _) => _FloatingNavBar(
                                  destinations: destinations,
                                  currentIndex: _currentIndex,
                                  unread: unread,
                                  onTap: (index) {
                                    if (!_pageCache.containsKey(index)) {
                                      _pageCache[index] = destinations[index].pageBuilder();
                                    }
                                    setState(() => _currentIndex = index);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.destinations,
    required this.currentIndex,
    required this.unread,
    required this.onTap,
  });

  final List<_ShellDestination> destinations;
  final int currentIndex;
  final int unread;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.black.withOpacity(0.25)
        : Colors.white.withOpacity(0.22);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.45);
    final selectedColor = isDark ? Colors.white : Colors.black;
    final unselectedColor = isDark
        ? Colors.white.withOpacity(0.45)
        : Colors.black.withOpacity(0.40);

    return Container(
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Row(
            children: List.generate(destinations.length, (i) {
              final item = destinations[i];
              final selected = i == currentIndex;
              final iconColor = selected ? selectedColor : unselectedColor;
              final labelColor = selected ? selectedColor : unselectedColor;

              Widget iconWidget;
              if (i == 2 && unread > 0) {
                iconWidget = Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(item.icon, color: iconColor, size: 23),
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                iconWidget = Icon(item.icon, color: iconColor, size: 23);
              }

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        iconWidget,
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: labelColor,
                            fontSize: selected ? 10.5 : 10,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ShellDestination {
  _ShellDestination({
    required this.label,
    required this.icon,
    required this.pageBuilder,
  });

  final String label;
  final IconData icon;
  final Widget Function() pageBuilder;
}
