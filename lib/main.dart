import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/cloud_sync_service.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'data/user_store.dart';
// import 'supabase_options.dart';
import 'theme/app_theme.dart';
import 'features/welcome/welcome_page.dart';

const String kGoogleWebClientId =
    '1018470167099-j9jnmsureoqshdc5mp7n4jotq6qsrhdi.apps.googleusercontent.com';
const String kAdminEmail = 'yaelmartin2003@gmail.com';

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

List<String> _toStringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return const <String>[];
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // En web preferimos permitir el primer frame rápido (priorizar tiempo a
  // primeros píxeles) y decodificar la imagen de bienvenida en segundo plano.
  // En plataformas móviles seguimos deferFirstFrame para evitar parpadeos.
  final bool shouldDeferFirstFrame = !kIsWeb;
  if (shouldDeferFirstFrame) {
    // Congela el primer frame hasta que todo esté listo — elimina el flash blanco
    // durante hot restart. El fondo negro nativo (styles.xml / index.html) se ve
    // mientras se espera.
    binding.deferFirstFrame();
  }

  // Modo edge-to-edge: el contenido se renderiza detrás de la barra de estado
  // y la barra de navegación (Dynamic Island, punch-hole, gesture bar).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Barras del sistema completamente transparentes — el fondo de la app se ve
  // debajo en lugar del color blanco del sistema.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Si ya está inicializado, ignora el error
    if (e.toString().contains('already exists')) {
      // Firebase ya estaba inicializado
    } else {
      rethrow;
    }
  }
  await loadAppThemePrefs();

  // Mostrar pantalla de bienvenida solo la primera vez y solo en builds *release*.
  // Esto evita que la pantalla aparezca durante recargas/hot-restart en desarrollo.
  final showWelcome = kReleaseMode && !(await hasSeenWelcome());

  runApp(GymCoachApp(showWelcome: showWelcome));

  // En plataformas no-web intentamos decodificar la imagen de bienvenida
  // antes de permitir el primer frame para evitar parpadeos. En web
  // permitimos el primer frame inmediatamente y decodificamos en segundo plano
  // para priorizar tiempo de carga.
  if (shouldDeferFirstFrame) {
    try {
      final bd = await rootBundle.load('assets/bienvenida 2.png');
      final bytes = bd.buffer.asUint8List();
      final completer = Completer<void>();
      ui.decodeImageFromList(bytes, (image) {
        completer.complete();
      });
      await completer.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}

    // Ahora sí permite renderizar el primer frame (ya tenemos tema y sesión)
    binding.allowFirstFrame();
  } else {
    // Web: permitir primer frame inmediatamente y lanzar decodificación en
    // background sin bloquear.
    unawaited(() async {
      try {
        final bd = await rootBundle.load('assets/bienvenida 2.png');
        final bytes = bd.buffer.asUint8List();
        ui.decodeImageFromList(bytes, (_) {});
      } catch (_) {}
    }());
  }

  unawaited(_bootstrapPersistedSession());
  unawaited(CloudSyncService.instance.initialize());
}

Future<void> _bootstrapPersistedSession() async {
  // Restaurar usuario persistido y, si es posible, restaurar sesión Google
  try {
    // Primero, cargar el id persistido (esto deja el UserStore con un id si existía)
    await UserStore.instance.loadPersistedCurrentUser();

    // Listener de cambios de auth para mantener UserStore sincronizado
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        // usuario desconectado: limpiar persistencia
        await UserStore.instance.clearPersistedCurrentUser();
      } else {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final data = doc.data();
          if (data != null) {
            final email = data['email'] is String
                ? data['email'] as String
                : (user.email ?? '');
            final isAdminByEmail =
                email.toLowerCase() == kAdminEmail.toLowerCase();
            if (isAdminByEmail && data['role'] != 'admin') {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                    'role': 'admin',
                    'email': email,
                  }, SetOptions(merge: true));
            }
            final roleStr = isAdminByEmail
                ? 'admin'
                  : (data['role'] is String ? data['role'] as String : 'sinclave');
            final appRole = appUserRoleFromString(roleStr);
            final appUser = AppUserData(
              id: user.uid,
              name: data['name'] is String
                  ? data['name'] as String
                  : (user.displayName ?? ''),
              email: email,
              role: appRole,
              age: _toInt(data['age']),
              level: data['level'] is String ? data['level'] as String : null,
              weightKg: _toDouble(data['weightKg']),
              heightCm: _toInt(data['heightCm']),
              objectives: _toStringList(data['objectives']),
              trainerId: data['entrenadorId'] is String
                  ? data['entrenadorId'] as String
                  : null,
              trainerCode: data['codigoEntrenador'] is String
                  ? data['codigoEntrenador'] as String
                  : null,
              photoUrl: data['photoUrl'] is String
                  ? data['photoUrl'] as String
                  : (user.photoURL ?? ''),
            );
            await UserStore.instance.setCurrentUserId(
              user.uid,
              data: appUser,
              persist: true,
            );
          } else {
            await UserStore.instance.setCurrentUserId(user.uid, persist: true);
          }
        } catch (_) {}
      }
    });

    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      // Si ya hay sesión de Firebase, cargar datos desde Firestore
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(current.uid)
            .get();
        final data = doc.data();
        if (data != null) {
          final email = data['email'] is String
              ? data['email'] as String
              : (current.email ?? '');
          final isAdminByEmail =
              email.toLowerCase() == kAdminEmail.toLowerCase();
          if (isAdminByEmail && data['role'] != 'admin') {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(current.uid)
                .set({
                  'role': 'admin',
                  'email': email,
                }, SetOptions(merge: true));
          }
          final roleStr = isAdminByEmail
              ? 'admin'
                : (data['role'] is String ? data['role'] as String : 'sinclave');
          final appRole = appUserRoleFromString(roleStr);
          final appUser = AppUserData(
            id: current.uid,
            name: data['name'] is String
                ? data['name'] as String
                : (current.displayName ?? ''),
            email: email,
            role: appRole,
            age: _toInt(data['age']),
            level: data['level'] is String ? data['level'] as String : null,
            weightKg: _toDouble(data['weightKg']),
            heightCm: _toInt(data['heightCm']),
            objectives: _toStringList(data['objectives']),
            trainerId: data['entrenadorId'] is String
                ? data['entrenadorId'] as String
                : null,
            trainerCode: data['codigoEntrenador'] is String
                ? data['codigoEntrenador'] as String
                : null,
            photoUrl: data['photoUrl'] is String
                ? data['photoUrl'] as String
                : (current.photoURL ?? ''),
          );
          await UserStore.instance.setCurrentUserId(
            current.uid,
            data: appUser,
            persist: true,
          );
        } else {
          await UserStore.instance.setCurrentUserId(current.uid, persist: true);
        }
      } catch (_) {}
    } else {
      // Intentar restaurar sesión Google en silencioso (si el usuario usó Google)
      try {
        final google = GoogleSignIn(clientId: kGoogleWebClientId);
        final acc = await google.signInSilently();
        if (acc != null) {
          final auth = await acc.authentication;
          final cred = GoogleAuthProvider.credential(
            accessToken: auth.accessToken,
            idToken: auth.idToken,
          );
          final userCred = await FirebaseAuth.instance.signInWithCredential(
            cred,
          );
          final user = userCred.user;
          if (user != null) {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            final data = doc.data();
            final email = data != null && data['email'] is String
                ? data['email'] as String
                : (user.email ?? '');
            final isAdminByEmail =
                email.toLowerCase() == kAdminEmail.toLowerCase();
            if (isAdminByEmail && (data == null || data['role'] != 'admin')) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({
                    'role': 'admin',
                    'email': email,
                  }, SetOptions(merge: true));
            }
            final roleStr = isAdminByEmail
                ? 'admin'
                    : (data != null && data['role'] is String
                      ? data['role'] as String
                      : 'sinclave');
            final appRole = appUserRoleFromString(roleStr);
            final appUser = AppUserData(
              id: user.uid,
              name: data != null && data['name'] is String
                  ? data['name'] as String
                  : (user.displayName ?? ''),
              email: email,
              role: appRole,
              age: _toInt(data?['age']),
              level: data != null && data['level'] is String
                  ? data['level'] as String
                  : null,
              weightKg: _toDouble(data?['weightKg']),
              heightCm: _toInt(data?['heightCm']),
              objectives: _toStringList(data?['objectives']),
              trainerId: data != null && data['entrenadorId'] is String
                  ? data['entrenadorId'] as String
                  : null,
              trainerCode: data != null && data['codigoEntrenador'] is String
                  ? data['codigoEntrenador'] as String
                  : null,
              photoUrl: data != null && data['photoUrl'] is String
                  ? data['photoUrl'] as String
                  : (user.photoURL ?? ''),
            );
            await UserStore.instance.setCurrentUserId(
              user.uid,
              data: appUser,
              persist: true,
            );
          }
        }
      } catch (_) {}

      // Si no hay sesión Firebase ni Google, intentar cargar datos del id persistido (si existe)
      try {
        final persistedId = UserStore.instance.currentUser.id;
        if (persistedId.isNotEmpty && persistedId != 'yael') {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(persistedId)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final email = data != null && data['email'] is String
                ? data['email'] as String
                : '';
            final isAdminByEmail =
                email.toLowerCase() == kAdminEmail.toLowerCase();
            final roleStr = isAdminByEmail
              ? 'admin'
              : (data != null && data['role'] is String
                  ? data['role'] as String
                  : 'sinclave');
            final appRole = appUserRoleFromString(roleStr);
            final appUser = AppUserData(
              id: persistedId,
              name: data != null && data['name'] is String
                  ? data['name'] as String
                  : '',
              email: email,
              role: appRole,
              age: _toInt(data?['age']),
              level: data != null && data['level'] is String
                  ? data['level'] as String
                  : null,
              weightKg: _toDouble(data?['weightKg']),
              heightCm: _toInt(data?['heightCm']),
              objectives: _toStringList(data?['objectives']),
              trainerId: data != null && data['entrenadorId'] is String
                  ? data['entrenadorId'] as String
                  : null,
              trainerCode: data != null && data['codigoEntrenador'] is String
                  ? data['codigoEntrenador'] as String
                  : null,
              photoUrl: data != null && data['photoUrl'] is String
                  ? data['photoUrl'] as String
                  : '',
            );
            await UserStore.instance.setCurrentUserId(
              persistedId,
              data: appUser,
              persist: true,
            );
          } else {
            // Si no hay documento, limpiar persistencia para evitar mostrar datos vacíos
            await UserStore.instance.clearPersistedCurrentUser();
          }
        }
      } catch (_) {}
    }
  } catch (_) {}
}
