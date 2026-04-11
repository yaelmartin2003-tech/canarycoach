import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import '../../data/supabase_storage_service.dart';
import '../../data/cloud_sync_service.dart';
import '../../data/cloudinary_service.dart';
import '../../data/user_store.dart';
import '../shared/questionnaire_editor_dialog.dart';
import '../../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../auth_example.dart';
import 'profile_edit_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late TextEditingController _nombreController;
  late TextEditingController _emailController;
  late TextEditingController _edadController;
  late TextEditingController _pesoController;
  late TextEditingController _alturaController;
  late TextEditingController _codigoRolController;

  String _nivelSeleccionado = 'Principiante';
  final Set<String> _objetivosSeleccionados = {};
  String _fotoInicial = 'LL';
  Uint8List? _fotoBytes;
  String _fotoUrl = '';
  bool _aplicandoCodigoRol = false;
  String? _selectedLanguage;

  // Validation errors
  final Map<String, String?> _errors = {
    'nombre': null,
    'email': null,
    'edad': null,
    'peso': null,
    'altura': null,
  };

  final List<String> _objetivos = [
    'Perder peso',
    'Ganar músculo',
    'Mantenimiento',
    'Aumentar fuerza',
    'Mejorar resistencia',
  ];

  String _carritoCodigoAdmin = '';

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _emailController = TextEditingController();
    _edadController = TextEditingController();
    _pesoController = TextEditingController();
    _alturaController = TextEditingController();
    _codigoRolController = TextEditingController();
    _selectedLanguage = 'Español';
    _cargarPerfilActual();
    _actualizarFotoInicial();
    final u = UserStore.instance.currentUser;
    // Si el admin no tiene codigoEntrenador, generarlo
    if (u.role == AppUserRole.admin) {
      _ensureAdminTrainerCode();
    }
  }

  /// Asegura que el admin tenga un `codigoEntrenador` en Firestore.
  /// Si no lo tiene, genera uno y lo guarda.
  Future<void> _ensureAdminTrainerCode() async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final existingCode =
          (userDoc.data()?['codigoEntrenador'] as String? ?? '').trim();
      if (existingCode.isNotEmpty) {
        // Verificar que el access_key todavía existe
        final keySnap = await FirebaseFirestore.instance
            .collection('access_keys')
            .doc(existingCode)
            .get();
        if (keySnap.exists) {
          if (mounted) setState(() => _carritoCodigoAdmin = existingCode);
          return;
        }
      }
      // Generar nuevo
      String newCode = _generarCodigoEntrenador();
      for (var i = 0; i < 8; i++) {
        final snap = await FirebaseFirestore.instance
            .collection('access_keys')
            .doc(newCode)
            .get();
        if (!snap.exists) break;
        newCode = _generarCodigoEntrenador();
      }
      // Guardar en Firestore: acceso_keys + campo en users
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('access_keys').doc(newCode),
        {'tipo': 'user', 'entrenadorId': authUser.uid, 'usado': false},
      );
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(authUser.uid),
        {'codigoEntrenador': newCode},
      );
      await batch.commit();
      // Actualizar UserStore en memoria
      final updated = UserStore.instance.currentUser.copyWith(
        trainerCode: newCode,
      );
      await UserStore.instance.setCurrentUserId(
        updated.id,
        data: updated,
        persist: false,
      );
      if (mounted) setState(() => _carritoCodigoAdmin = newCode);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _edadController.dispose();
    _pesoController.dispose();
    _alturaController.dispose();
    _codigoRolController.dispose();
    super.dispose();
  }

  String _generarCodigoEntrenador() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return 'ENTR-${List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join()}';
  }

  String _generarCodigoTrainerUpgrade() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return 'TRUP-${List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join()}';
  }

  Future<void> _generarNuevoCodigoTrainerUpgrade() async {
    try {
      String newCode = _generarCodigoTrainerUpgrade();
      // Asegurarse de que no existe ya en access_keys
      for (var i = 0; i < 8; i++) {
        final snap = await FirebaseFirestore.instance
            .collection('access_keys')
            .doc(newCode)
            .get();
        if (!snap.exists) break;
        newCode = _generarCodigoTrainerUpgrade();
      }
      // Solo guardar en access_keys (el panel admin detectará el cambio)
      await FirebaseFirestore.instance
          .collection('access_keys')
          .doc(newCode)
          .set({'tipo': 'trainer_upgrade', 'usado': false});
    } catch (_) {}
  }

  Future<void> _activarRolEntrenadorConCodigo() async {
    final code = _codigoRolController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un codigo de entrenador.')),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesion de nuevo.')),
      );
      return;
    }

    if (UserStore.instance.currentUser.role == AppUserRole.trainer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu cuenta ya es entrenador.')),
      );
      return;
    }

    setState(() => _aplicandoCodigoRol = true);
    try {
      final codeRef = FirebaseFirestore.instance
          .collection('access_keys')
          .doc(code);
      final codeSnap = await codeRef.get();
      if (!codeSnap.exists) {
        throw Exception('Codigo no valido');
      }

      final data = codeSnap.data() ?? <String, dynamic>{};
      final tipo = (data['tipo']?.toString() ?? '').toLowerCase();

      if (tipo == 'user') {
        String trainerId = (data['entrenadorId'] as String? ?? '').trim();
        if (trainerId.isEmpty) {
          trainerId = (data['trainerId'] as String? ?? '').trim();
        }
        if (trainerId.isEmpty) {
          // Fallback: intentar resolver el entrenador por users.codigoEntrenador
          final ownerSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('codigoEntrenador', isEqualTo: code)
              .limit(1)
              .get();
          if (ownerSnap.docs.isNotEmpty) {
            trainerId = ownerSnap.docs.first.id;
          }
        }
        if (trainerId.isEmpty) {
          throw Exception('Ese codigo no tiene entrenador asignado');
        }

        List<Map<String, String>> trainerTemplate =
            kDefaultQuestionnaireQuestions
                .map((q) => {'id': q.id, 'text': q.text})
                .toList();
        final trainerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(trainerId)
            .get();
        final rawTemplate = trainerDoc.data()?['trainerQuestionnaireTemplate'];
        if (rawTemplate is List) {
          final parsed = <Map<String, String>>[];
          for (final item in rawTemplate) {
            if (item is! Map) continue;
            final id = item['id']?.toString() ?? '';
            final text = item['text']?.toString() ?? '';
            if (id.trim().isEmpty || text.trim().isEmpty) continue;
            parsed.add({'id': id.trim(), 'text': text.trim()});
          }
          if (parsed.isNotEmpty) {
            trainerTemplate = parsed;
          }
        }

        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid);
        await FirebaseFirestore.instance.runTransaction((tx) async {
          tx.update(userRef, {
            'role': 'user',
            'entrenadorId': trainerId,
            'codigoEntrenador': code,
            'questionnaireQuestions': trainerTemplate,
            'questionnaireResponses': const <Map<String, String>>[],
          });
          tx.set(codeRef, {
            'lastUsedBy': currentUser.uid,
            'lastUsedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });

        final updated = UserStore.instance.currentUser.copyWith(
          role: AppUserRole.user,
          trainerId: trainerId,
          trainerCode: code,
        );
        await UserStore.instance.setCurrentUserId(
          updated.id,
          data: updated,
          persist: true,
        );

        if (!mounted) return;
        _codigoRolController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Te vinculaste correctamente con tu entrenador.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final usado = data['usado'] == true;
      if (tipo != 'trainer' && tipo != 'trainer_upgrade') {
        throw Exception('Ese codigo no es valido para esta accion');
      }
      if (usado) {
        throw Exception('Ese codigo ya fue usado');
      }

      String trainerCode = _generarCodigoEntrenador();
      for (var i = 0; i < 8; i++) {
        final existing = await FirebaseFirestore.instance
            .collection('access_keys')
            .doc(trainerCode)
            .get();
        if (!existing.exists) break;
        trainerCode = _generarCodigoEntrenador();
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(userRef, {
          'role': 'trainer',
          'codigoEntrenador': trainerCode,
          'entrenadorId': null,
        });
        tx.set(codeRef, {
          'usado': true,
          'usedBy': currentUser.uid,
          'usedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        tx.set(
          FirebaseFirestore.instance.collection('access_keys').doc(trainerCode),
          {'tipo': 'user', 'entrenadorId': currentUser.uid, 'usado': false},
          SetOptions(merge: true),
        );
      });

      // Generar nuevo código trainer_upgrade para el admin supremo
      await _generarNuevoCodigoTrainerUpgrade();

      final updated = UserStore.instance.currentUser.copyWith(
        role: AppUserRole.trainer,
        trainerCode: trainerCode,
        trainerId: null,
      );
      await UserStore.instance.setCurrentUserId(
        updated.id,
        data: updated,
        persist: true,
      );

      if (!mounted) return;
      _codigoRolController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rol actualizado a entrenador. Codigo usuarios: $trainerCode',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aplicar el codigo: $e')),
      );
    } finally {
      if (mounted) setState(() => _aplicandoCodigoRol = false);
    }
  }

  void _actualizarFotoInicial() {
    final nombre = _nombreController.text.trim();
    if (nombre.isNotEmpty) {
      final parts = nombre.split(' ').where((part) => part.isNotEmpty).toList();
      if (parts.length >= 2) {
        _fotoInicial = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        _fotoInicial = nombre.substring(0, 1).toUpperCase();
      }
    } else {
      _fotoInicial = 'LL';
    }
  }

  void _cargarPerfilActual() {
    final currentUser = UserStore.instance.currentUser;
    _nombreController.text = currentUser.name;
    _emailController.text = currentUser.email;
    _edadController.text = currentUser.age?.toString() ?? '';
    _pesoController.text = currentUser.weightKg?.toString() ?? '';
    _alturaController.text = currentUser.heightCm?.toString() ?? '';
    _nivelSeleccionado = currentUser.level ?? 'Principiante';
    _objetivosSeleccionados
      ..clear()
      ..addAll(currentUser.objectives);
    _fotoBytes = currentUser.photoBytes;
    _fotoUrl = currentUser.photoUrl;
  }

  // Validaciones
  bool _validarNombre(String valor) {
    if (valor.trim().isEmpty) {
      _errors['nombre'] = 'El nombre es requerido';
      return false;
    }
    if (valor.trim().length < 3) {
      _errors['nombre'] = 'El nombre debe tener al menos 3 caracteres';
      return false;
    }
    _errors['nombre'] = null;
    return true;
  }

  bool _validarEmail(String valor) {
    if (valor.trim().isEmpty) {
      _errors['email'] = 'El email es requerido';
      return false;
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(valor.trim())) {
      _errors['email'] = 'Email inválido';
      return false;
    }
    _errors['email'] = null;
    return true;
  }

  bool _validarEdad(String valor) {
    if (valor.trim().isEmpty) {
      _errors['edad'] = 'La edad es requerida';
      return false;
    }
    final edad = int.tryParse(valor);
    if (edad == null || edad < 15 || edad > 100) {
      _errors['edad'] = 'Debe estar entre 15 y 100 años';
      return false;
    }
    _errors['edad'] = null;
    return true;
  }

  bool _validarPeso(String valor) {
    if (valor.trim().isEmpty) {
      _errors['peso'] = null; // Optional field
      return true;
    }
    final peso = double.tryParse(valor);
    if (peso == null || peso < 30 || peso > 250) {
      _errors['peso'] = 'Peso debe estar entre 30 y 250 kg';
      return false;
    }
    _errors['peso'] = null;
    return true;
  }

  bool _validarAltura(String valor) {
    if (valor.trim().isEmpty) {
      _errors['altura'] = null; // Optional field
      return true;
    }
    final altura = int.tryParse(valor);
    if (altura == null || altura < 100 || altura > 250) {
      _errors['altura'] = 'Altura debe estar entre 100 y 250 cm';
      return false;
    }
    _errors['altura'] = null;
    return true;
  }

  bool _validarTodo() {
    final nombreValido = _validarNombre(_nombreController.text);
    final emailValido = _validarEmail(_emailController.text);
    final edadValida = _validarEdad(_edadController.text);
    final pesoValido = _validarPeso(_pesoController.text);
    final alturaValida = _validarAltura(_alturaController.text);

    return nombreValido &&
        emailValido &&
        edadValida &&
        pesoValido &&
        alturaValida;
  }

  void _guardarPerfil() {
    setState(() {
      if (_validarTodo()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Perfil guardado correctamente'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Show errors
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✗ Por favor revisa los campos marcados'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  Future<void> _seleccionarFotoLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo leer la imagen seleccionada.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _fotoBytes = bytes;
    });

    final url = await CloudinaryService.uploadImageBytes(
      bytes,
      fileName: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    if (!mounted) return;

    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo subir la foto a Cloudinary.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _fotoUrl = url;
      _fotoBytes = null;
    });

    UserStore.instance.updateCurrentProfilePhotoUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Foto de perfil subida correctamente.'),
        duration: Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _editarRespuestasCuestionario() async {
    final result = await showQuestionnaireEditorDialog(
      context,
      title: 'Editar respuestas del cuestionario',
      initialQuestions: UserStore.instance.currentUserQuestionnaireQuestions(),
      initialAnswers: UserStore.instance.currentUserQuestionnaireAnswers(),
      allowQuestionEditing: false,
      dismissible: true,
    );
    if (!mounted || result == null) return;
    UserStore.instance.saveCurrentUserQuestionnaire(
      questions: result.questions,
      answers: result.answers,
      markCompleted: true,
    );
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await UserStore.instance.clearPersistedCurrentUser();
    } catch (_) {}
    // Cancelar listeners en tiempo real para no recibir datos de esta cuenta
    CloudSyncService.instance.cancelRealtimeListeners();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthExamplePage()),
      (route) => false,
    );
  }

  Future<void> _openEditProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.modalBorderFor(context)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                  16, 14, 16,
                  24 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Editar perfil',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _InformacionPersonalPanel(
                      nombreController: _nombreController,
                      emailController: _emailController,
                      edadController: _edadController,
                      pesoController: _pesoController,
                      alturaController: _alturaController,
                      nivelSeleccionado: _nivelSeleccionado,
                      fotoInicial: _fotoInicial,
                      fotoBytes: _fotoBytes,
                      fotoUrl: _fotoUrl,
                      errors: _errors,
                      onNombreChanged: (_) {
                        setState(_actualizarFotoInicial);
                      },
                      onNivelChanged: (nivel) {
                        setState(() => _nivelSeleccionado = nivel);
                      },
                      onCambiarFoto: _seleccionarFotoLocal,
                      onNombreBlur: () => setState(
                        () => _validarNombre(_nombreController.text),
                      ),
                      onEmailBlur: () =>
                          setState(() => _validarEmail(_emailController.text)),
                      onEdadBlur: () =>
                          setState(() => _validarEdad(_edadController.text)),
                      onPesoBlur: () =>
                          setState(() => _validarPeso(_pesoController.text)),
                      onAlturaBlur: () => setState(
                        () => _validarAltura(_alturaController.text),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ObjetivosPanel(
                      objetivos: _objetivos,
                      seleccionados: _objetivosSeleccionados,
                      onObjectivoToggle: (objetivo) {
                        setState(() {
                          if (_objetivosSeleccionados.contains(objetivo)) {
                            _objetivosSeleccionados.remove(objetivo);
                          } else {
                            _objetivosSeleccionados.add(objetivo);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _guardarPerfil();
                          if (mounted) Navigator.of(sheetContext).pop();
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar cambios'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPersonalDataSheet() async {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.68);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.modalSurfaceFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.modalBorderFor(context)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Datos personales',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _ReadOnlyDataLine(
                  label: 'Nombre',
                  value: _nombreController.text,
                ),
                _ReadOnlyDataLine(
                  label: 'Correo',
                  value: _emailController.text,
                ),
                _ReadOnlyDataLine(label: 'Edad', value: _edadController.text),
                _ReadOnlyDataLine(label: 'Nivel', value: _nivelSeleccionado),
                _ReadOnlyDataLine(
                  label: 'Peso',
                  value: _pesoController.text.trim().isEmpty
                      ? '-'
                      : '${_pesoController.text} kg',
                ),
                _ReadOnlyDataLine(
                  label: 'Altura',
                  value: _alturaController.text.trim().isEmpty
                      ? '-'
                      : '${_alturaController.text} cm',
                ),
                _ReadOnlyDataLine(
                  label: 'Objetivos',
                  value: _objetivosSeleccionados.isEmpty
                      ? '-'
                      : _objetivosSeleccionados.join(', '),
                  isLast: true,
                  valueColor: muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openQuestionnaireSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.94,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: AppTheme.modalBorderFor(context)),
              ),
              child: ListenableBuilder(
                listenable: UserStore.instance,
                builder: (context, _) {
                  final user = UserStore.instance.currentUser;
                  final answers = {
                    for (final item in user.questionnaireResponses)
                      item.questionId: item.answer,
                  };
                  return SingleChildScrollView(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(
                      16, 14, 16,
                      24 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ver cuestionario',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        _QuestionnaireReadOnlyPanel(
                          questions: user.questionnaireQuestions,
                          answers: answers,
                          completedAt: user.questionnaireCompletedAt,
                          onEditResponses: _editarRespuestasCuestionario,
                          initiallyExpanded: true,
                          showToggleButton: false,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openRoleCodeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.modalSurfaceFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.modalBorderFor(context)),
        ),
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: UserStore.instance,
            builder: (context, _) {
              final user = UserStore.instance.currentUser;
              final Widget panel;
              if (user.role == AppUserRole.admin) {
                final code = _carritoCodigoAdmin.isNotEmpty
                    ? _carritoCodigoAdmin
                    : (user.trainerCode ?? '');
                panel = code.isEmpty
                    ? const SizedBox.shrink()
                    : _TrainerCodePanel(code: code);
              } else if (user.role == AppUserRole.trainer) {
                final code = user.trainerCode ?? '';
                panel = code.isEmpty
                    ? const SizedBox.shrink()
                    : _TrainerCodePanel(code: code);
              } else {
                panel = _RoleUpgradePanel(
                  codeController: _codigoRolController,
                  isSubmitting: _aplicandoCodigoRol,
                  onApply: _activarRolEntrenadorConCodigo,
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Clave personal',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    panel,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<T?> _showSelectionDialog<T>({
    required Rect anchorRect,
    required T selected,
    required List<_SelectionOption<T>> options,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final rightAnchor = Rect.fromLTWH(
      anchorRect.right - 10,
      anchorRect.top + 2,
      8,
      anchorRect.height - 4,
    );
    final position = RelativeRect.fromRect(
      rightAnchor,
      Offset.zero & overlay.size,
    );

    return showMenu<T>(
      context: context,
      position: position,
      color: Theme.of(context).cardColor.withValues(alpha: 0.98),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: AppTheme.surfaceBorderFor(context)),
      ),
      items: options.map((option) {
        final isSelected = option.value == selected;
        return PopupMenuItem<T>(
          value: option.value,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: isSelected
                    ? Icon(Icons.check_rounded, color: onSurface, size: 20)
                    : const SizedBox.shrink(),
              ),
              if (option.dotColor != null)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: option.dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                option.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openLanguageDialog(Rect anchorRect) async {
    final currentLanguage = _selectedLanguage ?? 'Español';
    final selected = await _showSelectionDialog<String>(
      anchorRect: anchorRect,
      selected: currentLanguage,
      options: const [_SelectionOption(value: 'Español', label: 'Español')],
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedLanguage = selected);
  }

  Future<void> _openModeDialog(AppThemePrefs prefs, Rect anchorRect) async {
    final selected = await _showSelectionDialog<ThemeMode>(
      anchorRect: anchorRect,
      selected: prefs.mode == ThemeMode.light
          ? ThemeMode.light
          : ThemeMode.dark,
      options: const [
        _SelectionOption(value: ThemeMode.dark, label: 'Oscuro'),
        _SelectionOption(value: ThemeMode.light, label: 'Claro'),
      ],
    );
    if (selected == null) return;
    await setAppThemeMode(selected);
  }

  Future<void> _openAccentDialog(AppThemePrefs prefs, Rect anchorRect) async {
    final selected = await _showSelectionDialog<AppAccentOption>(
      anchorRect: anchorRect,
      selected: prefs.accent,
      options: AppAccentOption.values
          .map(
            (option) => _SelectionOption<AppAccentOption>(
              value: option,
              label: option.label,
              dotColor: option.color,
            ),
          )
          .toList(),
    );
    if (selected == null) return;
    await setAppAccent(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final name = _nombreController.text.trim().isEmpty
        ? 'Tu nombre'
        : _nombreController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                _ProfileAvatar(
                  fotoBytes: _fotoBytes,
                  fotoUrl: _fotoUrl,
                  fotoInicial: _fotoInicial,
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 34,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfileEditPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(160, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Editar perfil'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Cuenta',
            style: theme.textTheme.titleLarge?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          _SettingsGlassCard(
            children: [
              _SettingsRow(
                icon: Icons.mail_outline,
                label: 'Correo electrónico',
                subtitle: _emailController.text.trim(),
              ),
              _SettingsRow(
                icon: Icons.person_outline,
                label: 'Datos personales',
                showChevron: true,
                onTap: _openPersonalDataSheet,
              ),
              _SettingsRow(
                icon: Icons.edit_note_outlined,
                label: 'Ver cuestionario',
                showChevron: true,
                onTap: _openQuestionnaireSheet,
              ),
              _SettingsRow(
                icon: Icons.lock_outline,
                label: 'Clave personal',
                showChevron: true,
                onTap: _openRoleCodeSheet,
                isLast: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Aplicación',
            style: theme.textTheme.titleLarge?.copyWith(
              color: onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<AppThemePrefs>(
            valueListenable: appThemePrefsNotifier,
            builder: (context, prefs, _) {
              final modeLabel = prefs.mode == ThemeMode.light
                  ? 'Claro'
                  : 'Oscuro';
              return _SettingsGlassCard(
                children: [
                  _SettingsRow(
                    icon: Icons.language_rounded,
                    label: 'Idioma de la aplicación',
                    valueText: _selectedLanguage ?? 'Español',
                    showChevron: true,
                    onTapRect: _openLanguageDialog,
                  ),
                  _SettingsRow(
                    icon: Icons.dark_mode_outlined,
                    label: 'Apariencia',
                    valueText: modeLabel,
                    showChevron: true,
                    onTapRect: (rect) => _openModeDialog(prefs, rect),
                  ),
                  _SettingsRow(
                    icon: Icons.palette_outlined,
                    label: 'Tonalidad',
                    valueText: prefs.accent.label,
                    valueDot: prefs.accent.color,
                    showChevron: true,
                    onTapRect: (rect) => _openAccentDialog(prefs, rect),
                    isLast: true,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _signOut,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.surfaceBorderFor(context)),
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                backgroundColor: theme.cardColor.withValues(alpha: 0.85),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(Icons.logout_rounded, color: onSurface),
                  const SizedBox(width: 10),
                  Text(
                    'Cerrar sesión',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SelectionOption<T> {
  const _SelectionOption({
    required this.value,
    required this.label,
    this.dotColor,
  });

  final T value;
  final String label;
  final Color? dotColor;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.fotoBytes,
    required this.fotoUrl,
    required this.fotoInicial,
  });

  final Uint8List? fotoBytes;
  final String fotoUrl;
  final String fotoInicial;

  @override
  Widget build(BuildContext context) {
    final size = 110.0;
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.78);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileEditPage()),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Theme.of(context).cardColor.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
            child: Center(
              child: fotoBytes != null
                  ? ClipOval(
                      child: Image.memory(
                        fotoBytes!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      ),
                    )
                  : fotoUrl.trim().isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            fotoUrl,
                            width: size,
                            height: size,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              fotoInicial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 40,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          fotoInicial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 40,
                          ),
                        ),
            ),
          ),
          Positioned(
            right: -6,
            bottom: -6,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.edit_rounded,
                  size: 18, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGlassCard extends StatelessWidget {
  const _SettingsGlassCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.surfaceBorderFor(context)),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.valueText,
    this.valueDot,
    this.showChevron = false,
    this.onTap,
    this.onTapRect,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? valueText;
  final Color? valueDot;
  final bool showChevron;
  final VoidCallback? onTap;
  final ValueChanged<Rect>? onTapRect;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Transform.translate(
                offset: const Offset(0, 1.2),
                child: Icon(icon, color: onSurface, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, 1.8),
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 16.5,
                            ),
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: muted,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (valueDot != null)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: valueDot,
                    shape: BoxShape.circle,
                  ),
                ),
              if (valueText != null)
                Transform.translate(
                  offset: const Offset(0, 1.8),
                  child: Text(
                    valueText!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
              if (showChevron)
                Transform.translate(
                  offset: const Offset(0, 1.8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: muted,
                    size: 24,
                  ),
                ),
            ],
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Divider(
                height: 1,
                color: onSurface.withValues(alpha: 0.16),
              ),
            ),
        ],
      ),
    );
    if (onTap == null && onTapRect == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onTapDown: (details) {
        if (onTapRect == null) return;
        final box = context.findRenderObject() as RenderBox;
        final topLeft = box.localToGlobal(Offset.zero);
        onTapRect!(topLeft & box.size);
      },
      child: child,
    );
  }
}

class _ReadOnlyDataLine extends StatelessWidget {
  const _ReadOnlyDataLine({
    required this.label,
    required this.value,
    this.isLast = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isLast;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: onSurface.withValues(alpha: 0.12)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: onSurface.withValues(alpha: 0.70),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: valueColor ?? onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerCodePanel extends StatelessWidget {
  const _TrainerCodePanel({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isLight = theme.brightness == Brightness.light;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: isLight ? 1.35 : 1,
        ),
        boxShadow: AppTheme.surfaceShadowFor(
          context,
          alpha: 0.09,
          blurRadius: 12,
          offsetY: 3,
          addTopHighlight: true,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Tu código de usuarios',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Comparte este código con tus usuarios para que se vinculen contigo.',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.68),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.vpn_key_rounded,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    code,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  color: theme.colorScheme.primary,
                  tooltip: 'Copiar',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Código copiado'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleUpgradePanel extends StatelessWidget {
  const _RoleUpgradePanel({
    required this.codeController,
    required this.isSubmitting,
    required this.onApply,
  });

  final TextEditingController codeController;
  final bool isSubmitting;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.3 : 1,
        ),
        boxShadow: AppTheme.surfaceShadowFor(
          context,
          alpha: 0.09,
          blurRadius: 12,
          offsetY: 3,
          addTopHighlight: true,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.upgrade_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Clave personal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Codigo',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : onApply,
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aplicar codigo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearancePanel extends StatefulWidget {
  const _AppearancePanel({
    required this.prefs,
    required this.onModeChanged,
    required this.onAccentChanged,
  });

  final AppThemePrefs prefs;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<AppAccentOption> onAccentChanged;

  @override
  State<_AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends State<_AppearancePanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLight = widget.prefs.mode == ThemeMode.light;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.68);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: theme.brightness == Brightness.light ? 1.3 : 1,
        ),
        boxShadow: AppTheme.surfaceShadowFor(
          context,
          alpha: 0.09,
          blurRadius: 12,
          offsetY: 3,
          addTopHighlight: true,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: accent),
              SizedBox(width: 8),
              Text(
                'Apariencia',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _expanded = !_expanded);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: onSurface.withValues(alpha: 0.06),
                foregroundColor: onSurface,
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Editar apariencia',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _expanded ? 1.0 : 0.0,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isLight ? 'Modo claro' : 'Modo oscuro',
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value: isLight,
                              activeThumbColor: accent,
                              onChanged: widget.onModeChanged,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Color principal',
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: AppAccentOption.values.map((option) {
                            final selected = widget.prefs.accent == option;
                            return InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => widget.onAccentChanged(option),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: onSurface.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: selected
                                        ? option.color
                                        : AppTheme.surfaceBorderFor(context),
                                    width: selected ? 1.8 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: option.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      option.label,
                                      style: TextStyle(
                                        color: onSurface,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InformacionPersonalPanel extends StatelessWidget {
  final TextEditingController nombreController;
  final TextEditingController emailController;
  final TextEditingController edadController;
  final TextEditingController pesoController;
  final TextEditingController alturaController;
  final String nivelSeleccionado;
  final String fotoInicial;
  final Uint8List? fotoBytes;
  final String fotoUrl;
  final Map<String, String?> errors;
  final ValueChanged<String> onNombreChanged;
  final ValueChanged<String> onNivelChanged;
  final VoidCallback onCambiarFoto;
  final VoidCallback onNombreBlur;
  final VoidCallback onEmailBlur;
  final VoidCallback onEdadBlur;
  final VoidCallback onPesoBlur;
  final VoidCallback onAlturaBlur;

  const _InformacionPersonalPanel({
    required this.nombreController,
    required this.emailController,
    required this.edadController,
    required this.pesoController,
    required this.alturaController,
    required this.nivelSeleccionado,
    required this.fotoInicial,
    required this.fotoBytes,
    required this.fotoUrl,
    required this.errors,
    required this.onNombreChanged,
    required this.onNivelChanged,
    required this.onCambiarFoto,
    required this.onNombreBlur,
    required this.onEmailBlur,
    required this.onEdadBlur,
    required this.onPesoBlur,
    required this.onAlturaBlur,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: isLight ? 1.3 : 1,
        ),
        boxShadow: AppTheme.surfaceShadowFor(
          context,
          alpha: 0.09,
          blurRadius: 12,
          offsetY: 3,
          addTopHighlight: true,
        ),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Información Personal
          Row(
            children: [
              Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Información Personal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Foto de Perfil
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: fotoBytes != null
                      ? ClipOval(
                          child: Image.memory(
                            fotoBytes!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        )
                      : fotoUrl.trim().isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            fotoUrl,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Text(
                              fotoInicial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          fotoInicial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 28,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: onCambiarFoto,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A2A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Cambiar foto',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Nombre Completo
          _buildTextField(
            context,
            label: 'Nombre Completo',
            controller: nombreController,
            placeholder: 'Nombre completo',
            isRequired: true,
            error: errors['nombre'],
            onChanged: onNombreChanged,
            onBlur: onNombreBlur,
          ),
          const SizedBox(height: 14),

          // Email
          _buildTextField(
            context,
            label: 'Email',
            controller: emailController,
            placeholder: 'Email',
            isRequired: true,
            error: errors['email'],
            keyboardType: TextInputType.emailAddress,
            onBlur: onEmailBlur,
          ),
          const SizedBox(height: 14),

          // Edad
          _buildTextField(
            context,
            label: 'Edad',
            controller: edadController,
            placeholder: 'Edad',
            isRequired: true,
            error: errors['edad'],
            keyboardType: TextInputType.number,
            onBlur: onEdadBlur,
          ),
          const SizedBox(height: 14),

          // Nivel de Entrenamiento
          _buildDropdown(
            context,
            label: 'Nivel de Entrenamiento',
            value: nivelSeleccionado,
            options: const ['Principiante', 'Intermedio', 'Avanzado'],
            onChanged: onNivelChanged,
          ),
          const SizedBox(height: 14),

          // Peso
          _buildTextField(
            context,
            label: 'Peso (kg)',
            controller: pesoController,
            placeholder: 'Peso',
            error: errors['peso'],
            keyboardType: TextInputType.number,
            onBlur: onPesoBlur,
          ),
          const SizedBox(height: 14),

          // Altura
          _buildTextField(
            context,
            label: 'Altura (cm)',
            controller: alturaController,
            placeholder: 'Altura',
            error: errors['altura'],
            keyboardType: TextInputType.number,
            onBlur: onAlturaBlur,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String placeholder,
    bool isRequired = false,
    String? error,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    VoidCallback? onBlur,
  }) {
    final hasError = error != null && error.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          onEditingComplete: onBlur,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(color: Color(0xFF6C6C6C)),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : Colors.transparent,
                width: hasError ? 2 : 0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError ? Colors.red : Colors.transparent,
                width: hasError ? 2 : 0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: hasError
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(12),
            errorText: error,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            onChanged: (newValue) {
              if (newValue != null) onChanged(newValue);
            },
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(option),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ObjetivosPanel extends StatelessWidget {
  final List<String> objetivos;
  final Set<String> seleccionados;
  final ValueChanged<String> onObjectivoToggle;

  const _ObjetivosPanel({
    required this.objetivos,
    required this.seleccionados,
    required this.onObjectivoToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Objetivo de entrenamiento',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: objetivos
                .map(
                  (objetivo) => GestureDetector(
                    onTap: () => onObjectivoToggle(objetivo),
                    child: Container(
                      decoration: BoxDecoration(
                        color: seleccionados.contains(objetivo)
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        objetivo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _QuestionnaireReadOnlyPanel extends StatefulWidget {
  const _QuestionnaireReadOnlyPanel({
    required this.questions,
    required this.answers,
    required this.completedAt,
    required this.onEditResponses,
    this.initiallyExpanded = false,
    this.showToggleButton = true,
  });

  final List<QuestionnaireQuestion> questions;
  final Map<String, String> answers;
  final DateTime? completedAt;
  final VoidCallback onEditResponses;
  final bool initiallyExpanded;
  final bool showToggleButton;

  @override
  State<_QuestionnaireReadOnlyPanel> createState() =>
      _QuestionnaireReadOnlyPanelState();
}

class _QuestionnaireReadOnlyPanelState
    extends State<_QuestionnaireReadOnlyPanel> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.68);

    final answered = widget.answers.values
        .where((v) => v.trim().isNotEmpty)
        .length;
    final completedLabel = widget.completedAt == null
        ? 'Pendiente de completar'
        : 'Respondido el ${widget.completedAt!.day.toString().padLeft(2, '0')}/${widget.completedAt!.month.toString().padLeft(2, '0')}/${widget.completedAt!.year}';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: theme.brightness == Brightness.light ? 1.3 : 1,
        ),
        boxShadow: AppTheme.surfaceShadowFor(
          context,
          alpha: 0.09,
          blurRadius: 12,
          offsetY: 3,
          addTopHighlight: true,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.assignment_rounded, color: accent, size: 26),
                  Positioned(
                    right: -3,
                    bottom: -2,
                    child: Icon(Icons.edit_rounded, color: accent, size: 13),
                  ),
                ],
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cuestionario',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completedLabel,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$answered/${widget.questions.length} respuestas guardadas',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.showToggleButton) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _expanded = !_expanded);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: onSurface.withValues(alpha: 0.06),
                  foregroundColor: onSurface,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _expanded ? 'Ocultar cuestionario' : 'Ver cuestionario',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          if (_expanded) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: widget.onEditResponses,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(
                    color: AppTheme.surfaceBorderFor(context),
                    width: Theme.of(context).brightness == Brightness.light
                        ? 1.25
                        : 1,
                  ),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Editar respuestas'),
              ),
            ),
            const SizedBox(height: 8),
            ...widget.questions.map((q) {
              final a = (widget.answers[q.id] ?? '').trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.surfaceBorderFor(context),
                      width: Theme.of(context).brightness == Brightness.light
                          ? 1.25
                          : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.text,
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.isEmpty ? 'Sin respuesta' : a,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
