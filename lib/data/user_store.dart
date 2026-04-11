import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cloud_sync_service.dart';

enum AppUserRole { admin, trainer, user, sinclave }

final ValueNotifier<AppUserRole> appUserRoleNotifier =
  ValueNotifier<AppUserRole>(AppUserRole.sinclave);

AppUserRole appUserRoleFromString(String? role) {
  switch ((role ?? '').toLowerCase()) {
    case 'admin':
      return AppUserRole.admin;
    case 'trainer':
      return AppUserRole.trainer;
    case 'sinclave':
      return AppUserRole.sinclave;
    case 'user':
      return AppUserRole.user;
    default:
      return AppUserRole.sinclave;
  }
}

String appUserRoleToString(AppUserRole role) {
  switch (role) {
    case AppUserRole.admin:
      return 'admin';
    case AppUserRole.trainer:
      return 'trainer';
    case AppUserRole.user:
      return 'user';
    case AppUserRole.sinclave:
      return 'sinclave';
  }
}

class QuestionnaireQuestion {
  const QuestionnaireQuestion({required this.id, required this.text});
  final String id;
  final String text;

  QuestionnaireQuestion copyWith({String? id, String? text}) {
    return QuestionnaireQuestion(id: id ?? this.id, text: text ?? this.text);
  }
}

const List<QuestionnaireQuestion> kDefaultQuestionnaireQuestions = [
  QuestionnaireQuestion(
    id: 'q1',
    text:
        '¿Tienes alguna lesión, dolor o condición médica que se deba tener en cuenta?',
  ),
  QuestionnaireQuestion(
    id: 'q2',
    text: '¿Cuántos días entrenarías por semana?',
  ),
  QuestionnaireQuestion(
    id: 'q3',
    text: '¿Cuánto tiempo podrías dedicar por sesión de entrenamiento?',
  ),
  QuestionnaireQuestion(
    id: 'q4',
    text:
        '¿Tienes preferencias por algunos ejercicios que te gustaría que incluyera en las rutinas?',
  ),
  QuestionnaireQuestion(
    id: 'q5',
    text: '¿Algún ejercicio que prefieras evitar?',
  ),
  QuestionnaireQuestion(
    id: 'q6',
    text:
        '¿Entrenarías en casa o en gimnasio? Si es solo en casa, ¿qué material tienes disponible para entrenar?',
  ),
  QuestionnaireQuestion(
    id: 'q7',
    text: 'Cualquier información extra, déjamela por aquí.',
  ),
];

class QuestionnaireResponse {
  const QuestionnaireResponse({required this.questionId, required this.answer});
  final String questionId;
  final String answer;
}

class ScheduledRoutineAssignment {
  const ScheduledRoutineAssignment({
    required this.routineName,
    required this.date,
  });
  final String routineName;
  final DateTime date;
  DateTime get normalizedDate => DateTime(date.year, date.month, date.day);

  bool matches(String otherRoutineName, DateTime otherDate) {
    final norm = DateTime(otherDate.year, otherDate.month, otherDate.day);
    return routineName == otherRoutineName && normalizedDate == norm;
  }
}

class WorkoutCompletion {
  const WorkoutCompletion({
    required this.routineName,
    required this.date,
    this.totalSeconds = 0,
    this.rating = 5,
  });
  final String routineName;
  final DateTime date;
  final int totalSeconds;
  final int rating;

  DateTime get normalizedDate => DateTime(date.year, date.month, date.day);

  bool matches(String otherRoutineName, DateTime otherDate) {
    final norm = DateTime(otherDate.year, otherDate.month, otherDate.day);
    return routineName == otherRoutineName && normalizedDate == norm;
  }
}

class ExerciseWeightLogEntry {
  const ExerciseWeightLogEntry({
    required this.exerciseName,
    required this.date,
    required this.weightKg,
  });
  final String exerciseName;
  final DateTime date;
  final double weightKg;

  DateTime get normalizedDate => DateTime(date.year, date.month, date.day);
}

class UserTrackingEntry {
  const UserTrackingEntry({
    required this.date,
    this.photoBytes,
    this.photoUrl = '',
    this.weightKg,
    this.waistCm,
    this.hipsCm,
    this.armsCm,
    this.thighsCm,
    this.calvesCm,
    this.forearmCm,
    this.neckCm,
    this.chestCm,
    this.notes = '',
  });

  final DateTime date;
  final Uint8List? photoBytes;
  final String photoUrl;
  final double? weightKg;
  final double? waistCm;
  final double? hipsCm;
  final double? armsCm;
  final double? thighsCm;
  final double? calvesCm;
  final double? forearmCm;
  final double? neckCm;
  final double? chestCm;
  final String notes;

  DateTime get normalizedDate => DateTime(date.year, date.month, date.day);

  UserTrackingEntry copyWith({
    DateTime? date,
    Uint8List? photoBytes,
    String? photoUrl,
    double? weightKg,
    double? waistCm,
    double? hipsCm,
    double? armsCm,
    double? thighsCm,
    double? calvesCm,
    double? forearmCm,
    double? neckCm,
    double? chestCm,
    String? notes,
  }) {
    return UserTrackingEntry(
      date: date ?? this.date,
      photoBytes: photoBytes ?? this.photoBytes,
      photoUrl: photoUrl ?? this.photoUrl,
      weightKg: weightKg ?? this.weightKg,
      waistCm: waistCm ?? this.waistCm,
      hipsCm: hipsCm ?? this.hipsCm,
      armsCm: armsCm ?? this.armsCm,
      thighsCm: thighsCm ?? this.thighsCm,
      calvesCm: calvesCm ?? this.calvesCm,
      forearmCm: forearmCm ?? this.forearmCm,
      neckCm: neckCm ?? this.neckCm,
      chestCm: chestCm ?? this.chestCm,
      notes: notes ?? this.notes,
    );
  }
}

class EvolutionTestEntry {
  const EvolutionTestEntry({
    required this.id,
    required this.date,
    this.note = '',
    this.imageBytes,
    this.imageUrl = '',
    this.imageName = '',
  });
  final String id;
  final DateTime date;
  final String note;
  final Uint8List? imageBytes;
  final String imageUrl;
  final String imageName;

  EvolutionTestEntry copyWith({
    String? id,
    DateTime? date,
    String? note,
    Uint8List? imageBytes,
    String? imageUrl,
    String? imageName,
  }) {
    return EvolutionTestEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      note: note ?? this.note,
      imageBytes: imageBytes ?? this.imageBytes,
      imageUrl: imageUrl ?? this.imageUrl,
      imageName: imageName ?? this.imageName,
    );
  }
}

class EvolutionTest {
  const EvolutionTest({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.createdByAdmin = false,
    this.entries = const [],
  });
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final bool createdByAdmin;
  final List<EvolutionTestEntry> entries;

  EvolutionTest copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    bool? createdByAdmin,
    List<EvolutionTestEntry>? entries,
  }) {
    return EvolutionTest(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdByAdmin: createdByAdmin ?? this.createdByAdmin,
      entries: entries ?? this.entries,
    );
  }
}

class AppUserData {
  const AppUserData({
    required this.id,
    required this.name,
    required this.email,
    this.trainerId,
    this.trainerCode,
    required this.role,
    this.age,
    this.level,
    this.weightKg,
    this.heightCm,
    this.objectives = const [],
    this.photoBytes,
    this.photoUrl = '',
    this.scheduledRoutines = const [],
    this.completedWorkouts = const [],
    this.trackingHistory = const [],
    this.exerciseWeightLogs = const [],
    this.evolutionTests = const [],
    this.questionnaireQuestions = kDefaultQuestionnaireQuestions,
    this.questionnaireResponses = const [],
    this.questionnaireCompletedAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String? trainerId;
  final String? trainerCode;
  final AppUserRole role;
  final int? age;
  final String? level;
  final double? weightKg;
  final int? heightCm;
  final List<String> objectives;
  final Uint8List? photoBytes;
  final String photoUrl;
  final List<ScheduledRoutineAssignment> scheduledRoutines;
  final List<WorkoutCompletion> completedWorkouts;
  final List<UserTrackingEntry> trackingHistory;
  final List<ExerciseWeightLogEntry> exerciseWeightLogs;
  final List<EvolutionTest> evolutionTests;
  final List<QuestionnaireQuestion> questionnaireQuestions;
  final List<QuestionnaireResponse> questionnaireResponses;
  final DateTime? questionnaireCompletedAt;
  final DateTime? createdAt;

  AppUserData copyWith({
    String? id,
    String? name,
    String? email,
    String? trainerId,
    String? trainerCode,
    AppUserRole? role,
    int? age,
    String? level,
    double? weightKg,
    int? heightCm,
    List<String>? objectives,
    Uint8List? photoBytes,
    String? photoUrl,
    List<ScheduledRoutineAssignment>? scheduledRoutines,
    List<WorkoutCompletion>? completedWorkouts,
    List<UserTrackingEntry>? trackingHistory,
    List<ExerciseWeightLogEntry>? exerciseWeightLogs,
    List<EvolutionTest>? evolutionTests,
    List<QuestionnaireQuestion>? questionnaireQuestions,
    List<QuestionnaireResponse>? questionnaireResponses,
    DateTime? questionnaireCompletedAt,
    DateTime? createdAt,
  }) {
    return AppUserData(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      trainerId: trainerId ?? this.trainerId,
      trainerCode: trainerCode ?? this.trainerCode,
      role: role ?? this.role,
      age: age ?? this.age,
      level: level ?? this.level,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      objectives: objectives ?? this.objectives,
      photoBytes: photoBytes ?? this.photoBytes,
      photoUrl: photoUrl ?? this.photoUrl,
      scheduledRoutines: scheduledRoutines ?? this.scheduledRoutines,
      completedWorkouts: completedWorkouts ?? this.completedWorkouts,
      trackingHistory: trackingHistory ?? this.trackingHistory,
      exerciseWeightLogs: exerciseWeightLogs ?? this.exerciseWeightLogs,
      evolutionTests: evolutionTests ?? this.evolutionTests,
      questionnaireQuestions:
          questionnaireQuestions ?? this.questionnaireQuestions,
      questionnaireResponses:
          questionnaireResponses ?? this.questionnaireResponses,
        questionnaireCompletedAt:
          questionnaireCompletedAt ?? this.questionnaireCompletedAt,
        createdAt: createdAt ?? this.createdAt,
    );
  }
}

class UserStore extends ChangeNotifier {
  static const String _kPrefsCurrentUserIdKey = 'gymcoach_current_user_id';

  UserStore._internal() {
    appUserRoleNotifier.value = currentUser.role;
  }

  static final UserStore instance = UserStore._internal();

    List<QuestionnaireQuestion> _questionnaireTemplate =
      List<QuestionnaireQuestion>.from(kDefaultQuestionnaireQuestions);

    // Plantillas de cuestionario por entrenador (trainerId -> preguntas)
    final Map<String, List<QuestionnaireQuestion>> _trainerQuestionnaireTemplates = {};

  String _currentUserId = '';

  final List<AppUserData> _users = [];

  List<AppUserData> get users => List.unmodifiable(_users);

  AppUserData get currentUser {
    final found = _users.firstWhere(
      (u) => u.id == _currentUserId,
      orElse: () => _users.isNotEmpty ? _users.first : _defaultCurrentUser(),
    );
    return found;
  }

  Future<void> setCurrentUserId(
    String id, {
    AppUserData? data,
    bool persist = true,
  }) async {
    final index = _users.indexWhere((u) => u.id == id);
    if (data != null) {
      if (index >= 0) {
        final existing = _users[index];
        // Merge: actualizar solo datos de perfil, preservar datos ricos
        // (completedWorkouts, evolutionTests, trackingHistory, etc.)
        // que vienen vacíos cuando data viene de Firestore users/{uid}
        final merged = existing.copyWith(
          name: data.name,
          email: data.email,
          role: data.role,
          trainerId: data.trainerId,
          trainerCode: data.trainerCode,
          age: data.age,
          level: data.level,
          weightKg: data.weightKg,
          heightCm: data.heightCm,
          objectives: data.objectives.isNotEmpty ? data.objectives : null,
          photoUrl: data.photoUrl.isNotEmpty ? data.photoUrl : null,
          // Solo sobrescribir listas ricas si la nueva data las trae llenas
          scheduledRoutines: data.scheduledRoutines.isNotEmpty
              ? data.scheduledRoutines
              : null,
          completedWorkouts: data.completedWorkouts.isNotEmpty
              ? data.completedWorkouts
              : null,
          trackingHistory: data.trackingHistory.isNotEmpty
              ? data.trackingHistory
              : null,
          exerciseWeightLogs: data.exerciseWeightLogs.isNotEmpty
              ? data.exerciseWeightLogs
              : null,
          evolutionTests: data.evolutionTests.isNotEmpty
              ? data.evolutionTests
              : null,
          questionnaireQuestions: data.questionnaireQuestions.isNotEmpty
              ? data.questionnaireQuestions
              : null,
          questionnaireResponses: data.questionnaireResponses.isNotEmpty
              ? data.questionnaireResponses
              : null,
          questionnaireCompletedAt:
              data.questionnaireCompletedAt ?? existing.questionnaireCompletedAt,
        );
        _users[index] = merged;
      } else {
        _users.add(data);
      }
    } else {
      if (index == -1) {
        _users.add(
          AppUserData(id: id, name: '', email: '', role: AppUserRole.sinclave),
        );
      }
    }

    _currentUserId = id;
    appUserRoleNotifier.value = currentUser.role;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsCurrentUserIdKey, id);
    }
    notifyListeners();
  }

  Future<void> clearPersistedCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsCurrentUserIdKey);
  }

  /// Actualiza un usuario en la lista interna sin notificar listeners.
  /// Usar solo desde CloudSyncService con _applyingRemote=true para evitar bucles.
  void updateUserInPlace(AppUserData updated) {
    final index = _users.indexWhere((u) => u.id == updated.id);
    if (index >= 0) {
      _users[index] = updated;
    } else {
      _users.add(updated);
    }
    notifyListeners();
  }

  Future<void> loadPersistedCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kPrefsCurrentUserIdKey);
    if (id != null && id.isNotEmpty) {
      await setCurrentUserId(id, persist: false);
    }
  }

  AppUserData _defaultCurrentUser() {
    return const AppUserData(
      id: '',
      name: '',
      email: '',
      role: AppUserRole.sinclave,
    );
  }

  void replaceAllFromCloud({
    required List<AppUserData> users,
    List<QuestionnaireQuestion>? questionnaireTemplate,
  }) {
    // Preservar datos ricos en memoria antes de reemplazar
    final existingById = <String, AppUserData>{
      for (final u in _users) u.id: u,
    };
    final fallbackCurrent = existingById[_currentUserId] ?? _defaultCurrentUser();

    final merged = users.map((incoming) {
      final existing = existingById[incoming.id];
      if (existing == null) return incoming;
      // Actualizar solo perfil, preservar datos ricos
      return existing.copyWith(
        name: incoming.name,
        email: incoming.email,
        role: incoming.role,
        trainerId: incoming.trainerId,
        trainerCode: incoming.trainerCode,
        age: incoming.age,
        level: incoming.level,
        weightKg: incoming.weightKg,
        heightCm: incoming.heightCm,
        objectives: incoming.objectives.isNotEmpty ? incoming.objectives : null,
        photoUrl: incoming.photoUrl.isNotEmpty ? incoming.photoUrl : null,
        // Solo sobrescribir listas ricas si la versión entrante las trae
        scheduledRoutines: incoming.scheduledRoutines.isNotEmpty
            ? incoming.scheduledRoutines
            : null,
        completedWorkouts: incoming.completedWorkouts.isNotEmpty
            ? incoming.completedWorkouts
            : null,
        trackingHistory: incoming.trackingHistory.isNotEmpty
            ? incoming.trackingHistory
            : null,
        exerciseWeightLogs: incoming.exerciseWeightLogs.isNotEmpty
            ? incoming.exerciseWeightLogs
            : null,
        evolutionTests: incoming.evolutionTests.isNotEmpty
            ? incoming.evolutionTests
            : null,
        questionnaireQuestions: incoming.questionnaireQuestions.isNotEmpty
            ? incoming.questionnaireQuestions
            : null,
        questionnaireResponses: incoming.questionnaireResponses.isNotEmpty
            ? incoming.questionnaireResponses
            : null,
        questionnaireCompletedAt:
            incoming.questionnaireCompletedAt ?? existing.questionnaireCompletedAt,
      );
    }).toList();

    _users
      ..clear()
      ..addAll(merged);
    if (!_users.any((u) => u.id == _currentUserId)) {
      _users.insert(0, fallbackCurrent);
    }
    if (questionnaireTemplate != null && questionnaireTemplate.isNotEmpty) {
      _questionnaireTemplate = List<QuestionnaireQuestion>.from(
        questionnaireTemplate,
      );
    }
    appUserRoleNotifier.value = currentUser.role;
    notifyListeners();
  }

  Future<void> loadAllUsersFromFirestore() async {
    try {
      final role = currentUser.role;
      final myUid = _currentUserId;
      final usersCol = FirebaseFirestore.instance.collection('users');
      // Limpiar documento huérfano de prueba si existe
      await usersCol.doc('yael').get().then((d) {
        if (d.exists) d.reference.delete();
      }).catchError((_) {});

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      if (role == AppUserRole.trainer) {
        // Entrenador: solo sus usuarios asignados (el propio entrenador se agrega luego).
        docs = (await usersCol.where('entrenadorId', isEqualTo: myUid).get()).docs;
      } else if (role == AppUserRole.admin) {
        // Admin: todos los entrenadores + usuarios asignados al admin.
        final trainersSnap = await usersCol
            .where('role', isEqualTo: appUserRoleToString(AppUserRole.trainer))
            .get();
        final myUsersSnap = await usersCol
            .where('entrenadorId', isEqualTo: myUid)
            .get();
        // También traer usuarios marcados explícitamente como 'sinclave'
        // para que el admin pueda ver a los huérfanos/usuarios sin asignar.
        final sinClaveSnap = await usersCol
            .where('role', isEqualTo: appUserRoleToString(AppUserRole.sinclave))
            .get();

        final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in trainersSnap.docs) {
          merged[d.id] = d;
        }
        for (final d in myUsersSnap.docs) {
          merged[d.id] = d;
        }
        for (final d in sinClaveSnap.docs) {
          merged[d.id] = d;
        }
        docs = merged.values.toList();
      } else {
        // Usuario normal: no listar catalogo de usuarios.
        docs = const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }

      // Preservar datos ricos en memoria antes de limpiar la lista.
      // La colección `users` de Firestore solo guarda perfil básico;
      // scheduledRoutines, completedWorkouts, trackingHistory, evolutionTests,
      // exerciseWeightLogs, etc. se guardan en app_state/users por CloudSyncService.
      // Al refrescar desde `users`, fusionamos con los datos ya en memoria.
      final existingById = <String, AppUserData>{
        for (final u in _users) u.id: u,
      };

      _users.clear();
      for (final d in docs) {
        final data = d.data();
        final roleStr = data['role'] is String ? data['role'] as String : 'sinclave';
        final role = appUserRoleFromString(roleStr);
        final existing = existingById[d.id];

        final profileName = data['name'] is String ? data['name'] as String : '';
        final profileEmail = data['email'] is String
            ? data['email'] as String
            : (data['correo'] is String ? data['correo'] as String : '');
        final profileTrainerId = data['entrenadorId'] is String
            ? data['entrenadorId'] as String
            : null;
        final profileTrainerCode = data['codigoEntrenador'] is String
            ? data['codigoEntrenador'] as String
            : null;
        final profileAge = data['age'] is int
            ? data['age'] as int
            : (data['age'] is num
                  ? (data['age'] as num).toInt()
                  : int.tryParse('${data['age'] ?? ''}'));
        final profileLevel = data['level'] is String ? data['level'] as String : null;
        final profileWeightKg = data['weightKg'] is num
            ? (data['weightKg'] as num).toDouble()
            : double.tryParse('${data['weightKg'] ?? ''}');
        final profileHeightCm = data['heightCm'] is int
            ? data['heightCm'] as int
            : (data['heightCm'] is num
                  ? (data['heightCm'] as num).toInt()
                  : int.tryParse('${data['heightCm'] ?? ''}'));
        final profileObjectives = data['objectives'] is List
            ? (data['objectives'] as List).map((e) => e.toString()).toList()
            : const <String>[];
        final profilePhotoUrl = data['photoUrl'] is String ? data['photoUrl'] as String : '';

        // Si el documento corresponde a un entrenador y tiene una plantilla
        // de cuestionario, cargarla en memoria para aplicarla a sus usuarios.
        if (role == AppUserRole.trainer) {
          // Compatibilidad: aceptar tanto 'trainerQuestionnaireTemplate'
          // (clave usada históricamente) como 'questionnaireTemplate'.
          final rawTpl = data['trainerQuestionnaireTemplate'] ?? data['questionnaireTemplate'];
          if (rawTpl is List) {
            try {
              final parsed = <QuestionnaireQuestion>[];
              for (final e in rawTpl) {
                if (e is Map) {
                  final id = e['id']?.toString() ?? 'q${parsed.length + 1}';
                  final text = e['text']?.toString() ?? '';
                  if (text.trim().isNotEmpty) parsed.add(QuestionnaireQuestion(id: id, text: text));
                } else if (e is String) {
                  final id = 'q${parsed.length + 1}';
                  final text = e;
                  if (text.trim().isNotEmpty) parsed.add(QuestionnaireQuestion(id: id, text: text));
                }
              }
              if (parsed.isNotEmpty) {
                _trainerQuestionnaireTemplates[d.id] = parsed;
              }
            } catch (_) {}
          }
        }

        final AppUserData user;
        if (existing != null) {
          // Fusionar: actualizar solo datos de perfil, preservar datos ricos.
          user = existing.copyWith(
            name: profileName,
            email: profileEmail,
            trainerId: profileTrainerId,
            trainerCode: profileTrainerCode,
            role: role,
            age: profileAge,
            level: profileLevel,
            weightKg: profileWeightKg,
            heightCm: profileHeightCm,
            objectives: profileObjectives,
            photoUrl: profilePhotoUrl,
          );
        } else {
          user = AppUserData(
            id: d.id,
            name: profileName,
            email: profileEmail,
            trainerId: profileTrainerId,
            trainerCode: profileTrainerCode,
            role: role,
            age: profileAge,
            level: profileLevel,
            weightKg: profileWeightKg,
            heightCm: profileHeightCm,
            objectives: profileObjectives,
            photoUrl: profilePhotoUrl,
          );
        }
        _users.add(user);
      }

      // Mantener el propio usuario en la lista para que el entrenador vea su tarjeta
      // y para no perder el contexto de rol tras recargar desde Firestore.
      if (myUid.isNotEmpty && !_users.any((u) => u.id == myUid)) {
        final meDoc = await usersCol.doc(myUid).get();
        if (meDoc.exists) {
          final data = meDoc.data() ?? <String, dynamic>{};
          final existingMe = existingById[meDoc.id];
          final meProfileName = data['name'] is String ? data['name'] as String : '';
          final meProfileEmail = data['email'] is String
              ? data['email'] as String
              : (data['correo'] is String ? data['correo'] as String : '');
          final meProfileRole = appUserRoleFromString(data['role']?.toString());
          final AppUserData meUser;
          if (existingMe != null) {
            meUser = existingMe.copyWith(
              name: meProfileName,
              email: meProfileEmail,
              trainerId: data['entrenadorId'] is String ? data['entrenadorId'] as String : null,
              trainerCode: data['codigoEntrenador'] is String ? data['codigoEntrenador'] as String : null,
              role: meProfileRole,
              age: data['age'] is int ? data['age'] as int : (data['age'] is num ? (data['age'] as num).toInt() : int.tryParse('${data['age'] ?? ''}')),
              level: data['level'] is String ? data['level'] as String : null,
              weightKg: data['weightKg'] is num ? (data['weightKg'] as num).toDouble() : double.tryParse('${data['weightKg'] ?? ''}'),
              heightCm: data['heightCm'] is int ? data['heightCm'] as int : (data['heightCm'] is num ? (data['heightCm'] as num).toInt() : int.tryParse('${data['heightCm'] ?? ''}')),
              objectives: data['objectives'] is List ? (data['objectives'] as List).map((e) => e.toString()).toList() : const <String>[],
              photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : '',
            );
          } else {
            meUser = AppUserData(
              id: meDoc.id,
              name: meProfileName,
              email: meProfileEmail,
              trainerId: data['entrenadorId'] is String ? data['entrenadorId'] as String : null,
              trainerCode: data['codigoEntrenador'] is String ? data['codigoEntrenador'] as String : null,
              role: meProfileRole,
              age: data['age'] is int ? data['age'] as int : (data['age'] is num ? (data['age'] as num).toInt() : int.tryParse('${data['age'] ?? ''}')),
              level: data['level'] is String ? data['level'] as String : null,
              weightKg: data['weightKg'] is num ? (data['weightKg'] as num).toDouble() : double.tryParse('${data['weightKg'] ?? ''}'),
              heightCm: data['heightCm'] is int ? data['heightCm'] as int : (data['heightCm'] is num ? (data['heightCm'] as num).toInt() : int.tryParse('${data['heightCm'] ?? ''}')),
              objectives: data['objectives'] is List ? (data['objectives'] as List).map((e) => e.toString()).toList() : const <String>[],
              photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : '',
            );
          }
          _users.insert(0, meUser);
        }
      }
      // Aplicar plantillas por entrenador o plantilla base a usuarios que no
      // tengan preguntas explícitas en su perfil cargado.
      for (var i = 0; i < _users.length; i++) {
        final u = _users[i];
        if (u.questionnaireQuestions.isNotEmpty) continue;
        final trainerId = u.trainerId;
        if (trainerId != null && trainerId.isNotEmpty) {
          final trainerTpl = _trainerQuestionnaireTemplates[trainerId];
          if (trainerTpl != null && trainerTpl.isNotEmpty) {
            _users[i] = u.copyWith(questionnaireQuestions: trainerTpl);
            continue;
          }
        }
        if (_questionnaireTemplate.isNotEmpty) {
          _users[i] = u.copyWith(questionnaireQuestions: List<QuestionnaireQuestion>.from(_questionnaireTemplate));
        } else {
          _users[i] = u.copyWith(questionnaireQuestions: List<QuestionnaireQuestion>.from(kDefaultQuestionnaireQuestions));
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistUserToFirestore(AppUserData user) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).set({
        'email': user.email,
        'name': user.name,
        'role': appUserRoleToString(user.role),
        'entrenadorId': user.trainerId,
        'codigoEntrenador': user.trainerCode,
        'age': user.age,
        'level': user.level,
        'weightKg': user.weightKg,
        'heightCm': user.heightCm,
        'objectives': user.objectives,
        'photoUrl': user.photoUrl,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Marca en Firestore y en el store local a los usuarios que no tienen
  /// `trainerId` (huérfanos) con el role `sinclave`.
  ///
  /// Nota: si las reglas de Firestore no permiten que el cliente escriba
  /// `role` en documentos de otros usuarios, este método fallará silenciosamente.
  Future<void> setSinclaveForOrphansOnFirestore() async {
    try {
      final usersCol = FirebaseFirestore.instance.collection('users');
      for (var i = 0; i < _users.length; i++) {
        final u = _users[i];
        if (u.id.isEmpty) continue;
        final trainerId = u.trainerId?.trim();
        final isOrphan = trainerId == null || trainerId.isEmpty;
        if (!isOrphan) continue;
        if (u.role == AppUserRole.sinclave) continue;
        if (u.role == AppUserRole.admin || u.role == AppUserRole.trainer) continue;
        // Actualizar localmente
        _users[i] = u.copyWith(role: AppUserRole.sinclave);
        // Intentar persistir en Firestore (merge para no sobrescribir campos)
        try {
          await usersCol.doc(u.id).set({'role': 'sinclave'}, SetOptions(merge: true));
        } catch (_) {
          // Ignorar errores de permisos/lectura-escritura del cliente
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  List<QuestionnaireQuestion> questionnaireTemplateQuestions() {
    if (_questionnaireTemplate.isEmpty) {
      return List<QuestionnaireQuestion>.from(kDefaultQuestionnaireQuestions);
    }
    return List.unmodifiable(_questionnaireTemplate);
  }

  List<QuestionnaireQuestion> currentUserQuestionnaireQuestions() {
    final items = currentUser.questionnaireQuestions;
    if (items.isNotEmpty) return List.unmodifiable(items);
    final trainerId = currentUser.trainerId;
    if (trainerId != null && trainerId.isNotEmpty) {
      final trainerTemplate = _trainerQuestionnaireTemplates[trainerId];
      if (trainerTemplate != null && trainerTemplate.isNotEmpty) {
        return List.unmodifiable(trainerTemplate);
      }
    }
    if (_questionnaireTemplate.isNotEmpty) return List.unmodifiable(_questionnaireTemplate);
    return List.unmodifiable(kDefaultQuestionnaireQuestions);
  }

  Map<String, String> currentUserQuestionnaireAnswers() {
    return {
      for (final r in currentUser.questionnaireResponses)
        r.questionId: r.answer,
    };
  }

  List<QuestionnaireQuestion> questionnaireQuestionsForUser(int index) {
    if (index < 0 || index >= _users.length) {
      if (_questionnaireTemplate.isNotEmpty) return List.unmodifiable(_questionnaireTemplate);
      return List.unmodifiable(kDefaultQuestionnaireQuestions);
    }
    final user = _users[index];
    final items = user.questionnaireQuestions;
    if (items.isNotEmpty) return List.unmodifiable(items);
    final trainerId = user.trainerId;
    if (trainerId != null && trainerId.isNotEmpty) {
      final trainerTemplate = _trainerQuestionnaireTemplates[trainerId];
      if (trainerTemplate != null && trainerTemplate.isNotEmpty) {
        return List.unmodifiable(trainerTemplate);
      }
    }
    if (_questionnaireTemplate.isNotEmpty) return List.unmodifiable(_questionnaireTemplate);
    return List.unmodifiable(kDefaultQuestionnaireQuestions);
  }

  Map<String, String> questionnaireAnswersForUser(int index) {
    if (index < 0 || index >= _users.length) return const {};
    return {
      for (final r in _users[index].questionnaireResponses)
        r.questionId: r.answer,
    };
  }

  void saveQuestionnaireForUser(
    int index, {
    required List<QuestionnaireQuestion> questions,
    required Map<String, String> answers,
    bool markCompleted = true,
  }) {
    if (index < 0 || index >= _users.length) return;
    final sanitizedQuestions = questions
        .where((q) => q.text.trim().isNotEmpty)
        .map((q) => q.copyWith(text: q.text.trim()))
        .toList();
    final allowedIds = sanitizedQuestions.map((q) => q.id).toSet();
    final sanitizedResponses = <QuestionnaireResponse>[];
    for (final e in answers.entries) {
      final v = e.value.trim();
      if (!allowedIds.contains(e.key) || v.isEmpty) continue;
      sanitizedResponses.add(
        QuestionnaireResponse(questionId: e.key, answer: v),
      );
    }
    final user = _users[index];
    _users[index] = user.copyWith(
      questionnaireQuestions: sanitizedQuestions.isEmpty
          ? kDefaultQuestionnaireQuestions
          : sanitizedQuestions,
      questionnaireResponses: sanitizedResponses,
      questionnaireCompletedAt: markCompleted
          ? DateTime.now()
          : user.questionnaireCompletedAt,
    );
    notifyListeners();
  }

  void saveCurrentUserQuestionnaire({
    required List<QuestionnaireQuestion> questions,
    required Map<String, String> answers,
    bool markCompleted = true,
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    saveQuestionnaireForUser(
      index,
      questions: questions,
      answers: answers,
      markCompleted: markCompleted,
    );
  }

  void saveQuestionnaireTemplateForAllUsers({
    required List<QuestionnaireQuestion> questions,
  }) {
    final sanitizedQuestions = questions
        .where((q) => q.text.trim().isNotEmpty)
        .map((q) => q.copyWith(text: q.text.trim()))
        .toList();
    final effective = sanitizedQuestions.isEmpty
        ? List<QuestionnaireQuestion>.from(kDefaultQuestionnaireQuestions)
        : sanitizedQuestions;
    _questionnaireTemplate = effective;
    final allowedIds = effective.map((q) => q.id).toSet();
    for (var i = 0; i < _users.length; i++) {
      final user = _users[i];
      // No sobrescribir a usuarios cuyo entrenador tiene plantilla propia.
      final trainerId = user.trainerId;
      if (trainerId != null && trainerId.isNotEmpty && _trainerQuestionnaireTemplates.containsKey(trainerId)) {
        continue;
      }
      final kept = user.questionnaireResponses
          .where((r) => allowedIds.contains(r.questionId))
          .toList();
      _users[i] = user.copyWith(
        questionnaireQuestions: effective,
        questionnaireResponses: kept,
      );
    }
    notifyListeners();
  }

  Future<void> saveQuestionnaireTemplateForTrainer(
    String trainerId,
    List<QuestionnaireQuestion> questions,
  ) async {
    final sanitizedQuestions = questions
        .where((q) => q.text.trim().isNotEmpty)
        .map((q) => q.copyWith(text: q.text.trim()))
        .toList();
    final effective = sanitizedQuestions.isEmpty
        ? List<QuestionnaireQuestion>.from(kDefaultQuestionnaireQuestions)
        : sanitizedQuestions;

    // Guardar en memoria
    _trainerQuestionnaireTemplates[trainerId] = effective;

    // Persistir en Firestore en el documento del entrenador
    try {
      final serialized = effective.map((q) => {'id': q.id, 'text': q.text}).toList();
      // Persistir en ambos campos para compatibilidad con versiones anteriores
      final docRef = FirebaseFirestore.instance.collection('users').doc(trainerId);
      await docRef.set({
        'questionnaireTemplate': serialized,
        'trainerQuestionnaireTemplate': serialized,
      }, SetOptions(merge: true));
    } catch (_) {}

    // Aplicar la plantilla a sus usuarios en memoria (sin tocar otros entrenadores)
    final allowedIds = effective.map((q) => q.id).toSet();
    for (var i = 0; i < _users.length; i++) {
      final user = _users[i];
      if (user.trainerId == trainerId) {
        final kept = user.questionnaireResponses
            .where((r) => allowedIds.contains(r.questionId))
            .toList();
        _users[i] = user.copyWith(
          questionnaireQuestions: effective,
          questionnaireResponses: kept,
        );
      }
    }
    notifyListeners();
  }

  void addEvolutionTestForUser(
    int index, {
    required String title,
    required String description,
    bool createdByAdmin = false,
    Uint8List? imageBytes,
    String imageUrl = '',
    String imageName = '',
  }) {
    if (index < 0 || index >= _users.length) return;
    final now = DateTime.now();
    final testId = 'test-${now.microsecondsSinceEpoch}';
    final firstEntry = EvolutionTestEntry(
      id: 'entry-${now.microsecondsSinceEpoch}',
      date: now,
      note: description.trim(),
      imageBytes: imageBytes,
      imageUrl: imageUrl,
      imageName: imageName,
    );
    final test = EvolutionTest(
      id: testId,
      title: title.trim(),
      description: description.trim(),
      createdAt: now,
      createdByAdmin: createdByAdmin,
      entries: [firstEntry],
    );
    final user = _users[index];
    final tests = [test, ...user.evolutionTests]
      ..sort((l, r) => r.createdAt.compareTo(l.createdAt));
    _users[index] = user.copyWith(evolutionTests: tests);
    notifyListeners();
  }

  void addCurrentUserEvolutionTest({
    required String title,
    required String description,
    Uint8List? imageBytes,
    String imageUrl = '',
    String imageName = '',
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    addEvolutionTestForUser(
      index,
      title: title,
      description: description,
      createdByAdmin: false,
      imageBytes: imageBytes,
      imageUrl: imageUrl,
      imageName: imageName,
    );
  }

  void addEvolutionTestEntryForUser(
    int index, {
    required String testId,
    required String note,
    Uint8List? imageBytes,
    String imageUrl = '',
    String imageName = '',
    DateTime? date,
  }) {
    if (index < 0 || index >= _users.length) return;
    final user = _users[index];
    final now = date ?? DateTime.now();
    final tests = user.evolutionTests.map((t) {
      if (t.id != testId) return t;
      final newEntry = EvolutionTestEntry(
        id: 'entry-${now.microsecondsSinceEpoch}',
        date: now,
        note: note.trim(),
        imageBytes: imageBytes,
        imageUrl: imageUrl,
        imageName: imageName,
      );
      final entries = [newEntry, ...t.entries]
        ..sort((l, r) => r.date.compareTo(l.date));
      return t.copyWith(entries: entries);
    }).toList();
    _users[index] = user.copyWith(evolutionTests: tests);
    notifyListeners();
  }

  void addCurrentUserEvolutionTestEntry({
    required String testId,
    required String note,
    Uint8List? imageBytes,
    String imageUrl = '',
    String imageName = '',
    DateTime? date,
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    addEvolutionTestEntryForUser(
      index,
      testId: testId,
      note: note,
      imageBytes: imageBytes,
      imageUrl: imageUrl,
      imageName: imageName,
      date: date,
    );
  }

  void markCurrentUserWorkoutCompleted({
    required String routineName,
    required DateTime date,
    required int totalSeconds,
    int rating = 5,
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    final normalized = DateTime(date.year, date.month, date.day);
    final user = _users[index];
    final completions = [...user.completedWorkouts];
    final existingIndex = completions.indexWhere(
      (c) => c.matches(routineName, normalized),
    );
    final newCompletion = WorkoutCompletion(
      routineName: routineName,
      date: normalized,
      totalSeconds: totalSeconds,
      rating: rating,
    );
    if (existingIndex >= 0) {
      completions[existingIndex] = newCompletion;
    } else {
      completions.add(newCompletion);
    }
    _users[index] = user.copyWith(completedWorkouts: completions);
    notifyListeners();
  }

  void addCurrentUserExerciseWeight({
    required String exerciseName,
    required double weightKg,
    DateTime? date,
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    addExerciseWeightForUser(
      index,
      exerciseName: exerciseName,
      weightKg: weightKg,
      date: date,
    );
  }

  void addExerciseWeightForUser(
    int index, {
    required String exerciseName,
    required double weightKg,
    DateTime? date,
  }) {
    if (index < 0 || index >= _users.length) return;
    final user = _users[index];
    final entry = ExerciseWeightLogEntry(
      exerciseName: exerciseName,
      date: date ?? DateTime.now(),
      weightKg: weightKg,
    );
    final logs = [entry, ...user.exerciseWeightLogs]
      ..sort((l, r) => r.date.compareTo(l.date));
    _users[index] = user.copyWith(exerciseWeightLogs: logs);
    notifyListeners();
  }

  /// Renombra un ejercicio en todos los registros de peso de todos los usuarios.
  void renameExerciseInAllLogs(String oldName, String newName) {
    if (oldName == newName) return;
    var anyChanged = false;
    for (var i = 0; i < _users.length; i++) {
      final user = _users[i];
      final orig = user.exerciseWeightLogs;
      if (orig.isEmpty) continue;
      final updated = orig.map((e) {
        if (e.exerciseName == oldName) {
          return ExerciseWeightLogEntry(
            exerciseName: newName,
            date: e.date,
            weightKg: e.weightKg,
          );
        }
        return e;
      }).toList();
      var modified = false;
      for (var j = 0; j < updated.length; j++) {
        if (updated[j].exerciseName != orig[j].exerciseName) {
          modified = true;
          break;
        }
      }
      if (modified) {
        _users[i] = user.copyWith(exerciseWeightLogs: updated);
        anyChanged = true;
      }
    }
    if (anyChanged) {
      notifyListeners();
      unawaited(CloudSyncService.instance.saveNow());
    }
  }

  /// Elimina todos los registros de un ejercicio para el usuario actual.
  void removeCurrentUserExerciseWeightLogs(String exerciseName) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    final user = _users[index];
    final filtered = user.exerciseWeightLogs
        .where((e) => e.exerciseName != exerciseName)
        .toList();
    if (filtered.length == user.exerciseWeightLogs.length) return;
    _users[index] = user.copyWith(exerciseWeightLogs: filtered);
    notifyListeners();
    unawaited(CloudSyncService.instance.saveNow());
  }

  /// Elimina una entrada concreta de registro de peso del usuario actual.
  void removeCurrentUserExerciseWeightEntry(String exerciseName, DateTime date) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    final user = _users[index];
    final filtered = user.exerciseWeightLogs
        .where((e) => !(e.exerciseName == exerciseName && e.date == date))
        .toList();
    if (filtered.length == user.exerciseWeightLogs.length) return;
    _users[index] = user.copyWith(exerciseWeightLogs: filtered);
    notifyListeners();
    unawaited(CloudSyncService.instance.saveNow());
  }

  void updateCurrentProfile({
    required String name,
    required String email,
    required int age,
    required String level,
    double? weightKg,
    int? heightCm,
    required List<String> objectives,
  }) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(
      name: name,
      email: email,
      age: age,
      level: level,
      weightKg: weightKg,
      heightCm: heightCm,
      objectives: objectives,
    );
    unawaited(_persistUserToFirestore(_users[index]));
    appUserRoleNotifier.value = _users[index].role;
    notifyListeners();
  }

  void updateCurrentProfilePhoto(Uint8List? photoBytes) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(photoBytes: photoBytes);
    unawaited(_persistUserToFirestore(_users[index]));
    // Guardar también los datos ricos inmediatamente para propagar la foto
    // a través de user_rich_data/{uid} (best-effort).
    unawaited(CloudSyncService.instance.saveNow());
    notifyListeners();
  }

  void updateCurrentProfilePhotoUrl(String photoUrl) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    _users[index] = _users[index].copyWith(
      photoUrl: photoUrl,
      photoBytes: null,
    );
    unawaited(_persistUserToFirestore(_users[index]));
    // Guardar los datos ricos para que la URL se sincronice en tiempo real.
    unawaited(CloudSyncService.instance.saveNow());
    notifyListeners();
  }

  void addCurrentUserTrackingEntry(UserTrackingEntry entry) {
    final index = _users.indexWhere((u) => u.id == _currentUserId);
    if (index == -1) return;
    addTrackingEntryForUser(index, entry);
  }

  void addTrackingEntryForUser(int index, UserTrackingEntry entry) {
    if (index < 0 || index >= _users.length) return;
    final user = _users[index];
    final history = [entry, ...user.trackingHistory]
      ..sort((l, r) => r.normalizedDate.compareTo(l.normalizedDate));
    _users[index] = user.copyWith(trackingHistory: history);
    notifyListeners();
  }

  void updateUserRole(int index, AppUserRole role) {
    if (index < 0 || index >= _users.length) return;
    _users[index] = _users[index].copyWith(role: role);
    if (_users[index].id == _currentUserId) appUserRoleNotifier.value = role;
    notifyListeners();
  }

  void assignRoutineOnDates(
    int index,
    String routineName,
    Iterable<DateTime> dates,
  ) {
    if (index < 0 || index >= _users.length) return;
    final user = _users[index];
    final assignments = [...user.scheduledRoutines];
    for (final d in dates) {
      final normalized = DateTime(d.year, d.month, d.day);
      assignments.add(
        ScheduledRoutineAssignment(routineName: routineName, date: normalized),
      );
    }
    _users[index] = user.copyWith(scheduledRoutines: assignments);
    notifyListeners();
  }

  void removeRoutineAssignment(
    int index,
    ScheduledRoutineAssignment assignment,
  ) {
    if (index < 0 || index >= _users.length) return;
    final user = _users[index];
    _users[index] = user.copyWith(
      scheduledRoutines: user.scheduledRoutines
          .where(
            (item) => !item.matches(assignment.routineName, assignment.date),
          )
          .toList(),
    );
    notifyListeners();
  }

  bool isCurrentUser(AppUserData user) => user.id == _currentUserId;

  List<ScheduledRoutineAssignment> currentUserAssignmentsForDate(
    DateTime date,
  ) {
    final normalized = DateTime(date.year, date.month, date.day);
    return currentUser.scheduledRoutines
        .where((a) => a.normalizedDate == normalized)
        .toList();
  }

  bool isRoutineCompletedForCurrentUserOnDate(
    String routineName,
    DateTime date,
  ) {
    final normalized = DateTime(date.year, date.month, date.day);
    return currentUser.completedWorkouts.any(
      (c) => c.matches(routineName, normalized),
    );
  }

  Set<DateTime> currentUserCompletedDates() =>
      currentUser.completedWorkouts.map((c) => c.normalizedDate).toSet();

  List<UserTrackingEntry> currentUserTrackingHistory() {
    final history = [...currentUser.trackingHistory]
      ..sort((l, r) => r.normalizedDate.compareTo(l.normalizedDate));
    return history;
  }

  List<UserTrackingEntry> trackingHistoryForUser(int index) {
    if (index < 0 || index >= _users.length) return const <UserTrackingEntry>[];
    final history = [..._users[index].trackingHistory]
      ..sort((l, r) => r.normalizedDate.compareTo(l.normalizedDate));
    return history;
  }

  List<ExerciseWeightLogEntry> currentUserExerciseWeightLogs() {
    final logs = [...currentUser.exerciseWeightLogs]
      ..sort((l, r) => r.date.compareTo(l.date));
    return logs;
  }

  List<ExerciseWeightLogEntry> exerciseWeightLogsForUser(int index) {
    if (index < 0 || index >= _users.length) {
      return const <ExerciseWeightLogEntry>[];
    }
    final logs = [..._users[index].exerciseWeightLogs]
      ..sort((l, r) => r.date.compareTo(l.date));
    return logs;
  }

  List<EvolutionTest> currentUserEvolutionTests() {
    final tests = [...currentUser.evolutionTests]
      ..sort((l, r) => r.createdAt.compareTo(l.createdAt));
    return tests;
  }

  List<EvolutionTest> evolutionTestsForUser(int index) {
    if (index < 0 || index >= _users.length) return const <EvolutionTest>[];
    final tests = [..._users[index].evolutionTests]
      ..sort((l, r) => r.createdAt.compareTo(l.createdAt));
    return tests;
  }

  void deleteUser(int index) {
    if (index < 0 || index >= _users.length) return;
    _users.removeAt(index);
    notifyListeners();
  }
}
