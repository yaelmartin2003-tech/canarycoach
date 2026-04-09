import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_example.dart';

const String _kWelcomeSeenKey = 'welcome_seen';

/// Devuelve true si la pantalla de bienvenida ya se mostró antes.
Future<bool> hasSeenWelcome() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kWelcomeSeenKey) ?? false;
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _onBienvenido(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWelcomeSeenKey, true);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AuthExamplePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen de fondo ocupa toda la pantalla (sin oscurecer en modo oscuro)
          Image.asset(
            'assets/bienvenida 2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            width: double.infinity,
            height: double.infinity,
          ),
          // Botón BIENVENIDO anclado en la parte inferior
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: () => _onBienvenido(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'BIENVENIDO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
