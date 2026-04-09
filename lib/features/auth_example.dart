import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

import 'package:google_sign_in/google_sign_in.dart';
import '../data/cloud_sync_service.dart';
import '../data/user_store.dart';
// import 'admin/admin_page.dart';
// import 'home/home_page.dart';
// import 'training/training_page.dart';
import 'shell/app_shell.dart';

/// Ejemplo de registro y login con roles usando Firebase Auth y Firestore.
/// Integra este flujo con tu lógica de navegación y UserStore.
class AuthExamplePage extends StatefulWidget {
  const AuthExamplePage({super.key});

  @override
  State<AuthExamplePage> createState() => _AuthExamplePageState();
}

class _AuthExamplePageState extends State<AuthExamplePage> {
  static const String _googleWebClientId =
      '1018470167099-j9jnmsureoqshdc5mp7n4jotq6qsrhdi.apps.googleusercontent.com';
  bool _isRegisterMode = false;
  bool _checking = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _claveController = TextEditingController();
  final String _role = 'sinclave'; // user, trainer, admin, sinclave
  String _message = '';

  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Si Firebase ya tiene sesión activa, ir directo al AppShell
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user != null) {
        CloudSyncService.instance.reattachListeners();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const AppShell()),
        );
      } else {
        setState(() => _checking = false);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _claveController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/fondo.png'), context);
  }
  final String _adminEmail =
      'yaelmartin2003@gmail.com'; // Cambia aquí si tu correo admin es otro

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

  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'El correo no es válido.';
        case 'user-not-found':
          return 'No existe ninguna cuenta con ese correo.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Correo o contraseña incorrectos.';
        case 'email-already-in-use':
          return 'Ese correo ya está registrado.';
        case 'weak-password':
          return 'La contraseña es demasiado débil.';
        case 'too-many-requests':
          return 'Demasiados intentos. Prueba de nuevo en un momento.';
        case 'network-request-failed':
          return 'Error de red. Revisa tu conexión.';
      }
      return error.message ?? 'No se pudo completar la autenticación.';
    }
    return error.toString();
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        clientId: _googleWebClientId,
      ).signIn();
      if (googleUser == null) {
        setState(() => _message = 'Inicio de sesión cancelado.');
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user!;
      // Evitar duplicados: si existe un documento con el mismo email pero distinto uid,
      // migramos sus datos al nuevo uid para mantener el perfil.
      final usersCol = FirebaseFirestore.instance.collection('users');
      final docsWithEmail = await usersCol
          .where('email', isEqualTo: user.email)
          .get();
      Map<String, dynamic>? data;
      final docRef = usersCol.doc(user.uid);
      if (docsWithEmail.docs.isNotEmpty) {
        // Buscar manualmente el doc con el mismo uid, sin usar firstWhere/orElse
        QueryDocumentSnapshot<Map<String, dynamic>>? matchingDoc;
        for (final d in docsWithEmail.docs) {
          if (d.id == user.uid) {
            matchingDoc = d;
            break;
          }
        }
        final existingSameId = matchingDoc ?? docsWithEmail.docs.first;
        // Si el doc encontrado tiene distinto id, movemos sus datos al nuevo uid
        if (existingSameId.id != user.uid) {
          final existingData = existingSameId.data();
          await docRef.set(existingData);
          // eliminamos el documento antiguo para evitar duplicados
          await existingSameId.reference.delete();
          data = existingData;
        } else {
          data = existingSameId.data();
        }
      } else {
        // No existe doc con este email -> crear nuevo
        final newDoc = {
          'email': user.email,
          'name': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'role': _role,
        };
        await docRef.set(newDoc);
        data = newDoc;
      }
      final isAdminByEmail =
          (user.email ?? '').toLowerCase() == _adminEmail.toLowerCase();
      if (isAdminByEmail) {
        await docRef.set({
          'role': 'admin',
          'email': user.email,
        }, SetOptions(merge: true));
        data['role'] = 'admin';
      }
      final roleStr = data['role'] is String ? (data['role'] as String) : _role;
      final appRole = appUserRoleFromString(roleStr);
      final appUser = AppUserData(
        id: user.uid,
        name: data['name'] is String && (data['name'] as String).isNotEmpty
            ? data['name'] as String
            : (user.displayName ?? ''),
        email: user.email ?? '',
        role: appRole,
        age: _toInt(data['age']),
        level: data['level'] is String ? data['level'] as String : null,
        weightKg: _toDouble(data['weightKg']),
        heightCm: _toInt(data['heightCm']),
        objectives: _toStringList(data['objectives']),
        photoUrl: data['photoUrl'] is String
            ? data['photoUrl'] as String
            : (user.photoURL ?? ''),
        trainerId: data['entrenadorId'] is String
            ? data['entrenadorId'] as String
            : null,
        trainerCode: data['codigoEntrenador'] is String
            ? data['codigoEntrenador'] as String
            : null,
      );
      await UserStore.instance.setCurrentUserId(
        user.uid,
        data: appUser,
        persist: true,
      );
      CloudSyncService.instance.reattachListeners();
      setState(() => _message = 'Login con Google exitoso.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      setState(() => _message = 'Error Google: ${_friendlyAuthError(e)}');
    }
  }

  Future<void> _register() async {
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      if (email.isEmpty || password.isEmpty) {
        setState(() => _message = 'Introduce email y contraseña.');
        return;
      }
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final appUser = AppUserData(
        id: credential.user!.uid,
        name: '',
        email: email,
        role: AppUserRole.sinclave,
        photoUrl: '',
        trainerId: null,
        trainerCode: null,
      );
      await UserStore.instance.setCurrentUserId(
        credential.user!.uid,
        data: appUser,
        persist: true,
      );
      // Persistir en Firestore para dejar el role por defecto en el servidor
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({'email': email, 'role': 'sinclave', 'name': ''}, SetOptions(merge: true));
      CloudSyncService.instance.reattachListeners();
      setState(() => _message = 'Registro exitoso.');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      setState(() => _message = 'Error: ${_friendlyAuthError(e)}');
    }
  }

  Future<void> _login() async {
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      if (email.isEmpty || password.isEmpty) {
        setState(() => _message = 'Introduce email y contraseña.');
        return;
      }
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Si el correo es el del admin, forzar siempre el rol admin en Firestore
      if (email.toLowerCase() == _adminEmail.toLowerCase()) {
        // Asegurar que el rol es admin sin borrar otros campos (merge)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({'role': 'admin', 'email': email}, SetOptions(merge: true));
        // Cargar todos los datos actuales de Firestore
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .get();
        final data = doc.data() ?? {};
        final appUser = AppUserData(
          id: credential.user!.uid,
          name: data['name'] is String && (data['name'] as String).isNotEmpty
              ? data['name'] as String
              : (credential.user!.displayName ?? ''),
          email: email,
          role: AppUserRole.admin,
          age: _toInt(data['age']),
          level: data['level'] is String ? data['level'] as String : null,
          weightKg: _toDouble(data['weightKg']),
          heightCm: _toInt(data['heightCm']),
          objectives: _toStringList(data['objectives']),
          photoUrl: data['photoUrl'] is String
              ? data['photoUrl'] as String
              : '',
          trainerId: null,
          trainerCode: null,
        );
        await UserStore.instance.setCurrentUserId(
          credential.user!.uid,
          data: appUser,
          persist: true,
        );
        CloudSyncService.instance.reattachListeners();
        setState(() => _message = 'Login exitoso. Rol: admin');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AppShell()),
        );
        return;
      }
      // Si no es admin, seguir el flujo normal
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();
      if (!doc.exists) {
        final newDoc = {'email': email, 'role': 'sinclave', 'name': ''};
        await FirebaseFirestore.instance
        .collection('users')
        .doc(credential.user!.uid)
        .set(newDoc, SetOptions(merge: true));
      }
      final freshDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();
      final data = freshDoc.data();
        final role = data != null && data['role'] is String
          ? data['role'] as String
          : 'sinclave';
      final appRole = appUserRoleFromString(role);
      final appUser = AppUserData(
        id: credential.user!.uid,
        name: data != null && data['name'] is String
            ? data['name'] as String
            : '',
        email: data != null && data['email'] is String
            ? data['email'] as String
            : email,
        role: appRole,
        age: _toInt(data?['age']),
        level: data != null && data['level'] is String
            ? data['level'] as String
            : null,
        weightKg: _toDouble(data?['weightKg']),
        heightCm: _toInt(data?['heightCm']),
        objectives: _toStringList(data?['objectives']),
        photoUrl: data != null && data['photoUrl'] is String
            ? data['photoUrl'] as String
            : '',
        trainerId: data != null && data['entrenadorId'] is String
            ? data['entrenadorId'] as String
            : null,
        trainerCode: data != null && data['codigoEntrenador'] is String
            ? data['codigoEntrenador'] as String
            : null,
      );
      await UserStore.instance.setCurrentUserId(
        credential.user!.uid,
        data: appUser,
        persist: true,
      );
      CloudSyncService.instance.reattachListeners();
      setState(() => _message = 'Login exitoso. Rol: $role');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      setState(() => _message = 'Error: ${_friendlyAuthError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/fondo.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: Colors.transparent,
                          ),
                          child: const _HeaderLogo(),
                        ),
                      ),
                      const SizedBox(height: 32),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          _isRegisterMode ? 'Registro' : 'Iniciar Sesión',
                          key: ValueKey(_isRegisterMode),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFF1F1F1),
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _buildTextField(_emailController, 'e-mail'),
                      const SizedBox(height: 30),
                      _buildTextField(
                        _passwordController,
                        'Contraseña',
                        isPassword: true,
                      ),
                      const SizedBox(height: 36),
                      _MainActionButton(
                        text: _isRegisterMode ? 'Volver' : 'Iniciar sesión',
                        addShadow: true,
                        onPressed: () {
                          if (_isRegisterMode) {
                            setState(() {
                              _isRegisterMode = false;
                              _claveController.clear();
                              _message = '';
                            });
                          } else {
                            _login();
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      _MainActionButton(
                        text: 'Registrarse',
                        onPressed: () {
                          if (!_isRegisterMode) {
                            setState(() {
                              _isRegisterMode = true;
                              _claveController.clear();
                              _message = '';
                            });
                          } else {
                            _register();
                          }
                        },
                      ),
                      const SizedBox(height: 36),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _signInWithGoogle,
                          icon: const _GoogleGlyph(),
                          label: const Text(
                            'Iniciar con Google',
                            style: TextStyle(
                              color: Color(0xFF0D0E12),
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFF2F2F2),
                            minimumSize: const Size(double.infinity, 54),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      if (_message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _message,
                            style: const TextStyle(
                              color: Color(0xFFFFD7D7),
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFFF2F2F2),
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFD0D0D0), width: 1.3),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFF2F2F2), width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      style: const TextStyle(
        fontSize: 18,
        color: Color(0xFFFAFAFA),
        fontWeight: FontWeight.w600,
      ),
      keyboardType: isPassword
          ? TextInputType.visiblePassword
          : TextInputType.text,
    );
  }
}

class _MainActionButton extends StatelessWidget {
  const _MainActionButton({
    required this.text,
    required this.onPressed,
    this.addShadow = false,
  });

  final String text;
  final VoidCallback onPressed;
  final bool addShadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: addShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 9),
                ),
              ]
            : null,
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFF1F1F1),
          minimumSize: const Size(double.infinity, 54),
          shape: const StadiumBorder(),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF0D0D11),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HeaderLogo extends StatelessWidget {
  const _HeaderLogo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.asset(
        'assets/LOGO APP.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            SizedBox.expand(child: CustomPaint(painter: _CcLogoPainter())),
      ),
    );
  }
}

class _CcLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // C abre hacia la derecha: arranca ~40° debajo del eje X, barre ~280°
    const startAngle = pi * 0.22;
    const sweepAngle = pi * 1.56;

    final r1 = w * 0.295; // radio C blanca (la más grande)
    final r2 = w * 0.225; // radio C azul
    final r3 = w * 0.220; // radio C amarilla
    final sw1 = r1 * 0.52; // grosor proporcional al radio
    final sw2 = r2 * 0.52;
    final sw3 = r3 * 0.52;

    // Centros: distribuidos horizontalmente, verticalmente centrados
    final cy = h * 0.5;
    final cx1 = w * 0.30; // C blanca  (izquierda)
    final cx2 = w * 0.52; // C azul    (centro)
    final cx3 = w * 0.72; // C amarilla (derecha)

    // Amarilla (fondo)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx3, cy), radius: r3),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw3
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xFFFFCC00),
    );

    // Azul (capa media)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx2, cy), radius: r2),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw2
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xFF1A72E8),
    );

    // Blanca (frente)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx1, cy), radius: r1),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw1
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xFFF2F2F2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const SweepGradient(
        colors: [
          Color(0xFF4285F4),
          Color(0xFF34A853),
          Color(0xFFFBBC05),
          Color(0xFFEA4335),
          Color(0xFF4285F4),
        ],
        stops: [0.00, 0.28, 0.52, 0.78, 1.00],
        startAngle: 0.0,
        endAngle: 6.2831853,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}
