import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_store.dart';
import 'user_store.dart';
import 'workout_routine_store.dart';

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _kCacheExercises = 'cloud_cache_exercises_v2';
  static const String _kCacheRoutines = 'cloud_cache_routines_v2';
  static const String _kCacheUsers = 'cloud_cache_users_v2';
  static const String _kCacheQuestionnaireTemplate =
      'cloud_cache_questionnaire_template_v2';
  static const String _kCacheVersionKey = 'cloud_cache_done_v2';
  // Timestamp de la última vez que guardamos en caché local
  static const String _kCacheLocalUpdatedAt = 'cloud_local_updated_at_v2';

  bool _initialized = false;
  bool _applyingRemote = false;
  bool _saveInFlight = false;
  bool _saveQueued = false;

  // Suscripciones en tiempo real a Firestore
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _exercisesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _routinesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _richDataSub;

  Future<void> initialize() async {
    if (_initialized) return;

    // Borrar datos de simulación de Firestore y caché antigua (sólo una vez)
    final prefs = await SharedPreferences.getInstance();
    final alreadyReset = prefs.getBool(_kCacheVersionKey) ?? false;
    if (!alreadyReset) {
      // Limpiar caché local antigua (v1)
      await prefs.remove('cloud_cache_exercises_v1');
      await prefs.remove('cloud_cache_routines_v1');
      await prefs.remove('cloud_cache_users_v1');
      await prefs.remove('cloud_cache_questionnaire_template_v1');
      // Borrar docs de Firestore con datos de simulación
      try {
        await _db.collection('app_state').doc('exercises').delete();
        await _db.collection('app_state').doc('routines').delete();
        await _db.collection('app_state').doc('users').delete();
      } catch (_) {}
      await prefs.setBool(_kCacheVersionKey, true);
      // Guardar stores vacíos como punto de partida limpio
      try {
        await _saveAll();
      } catch (_) {}
      _attachListeners();
      _initialized = true;
      return;
    }

    await _loadFromLocalCache();

    try {
      await _loadOrSeed();
    } catch (_) {
      // Si Firestore no esta disponible (offline/permisos), mantenemos modo local.
    }

    // Cargar datos ricos del usuario actual desde user_rich_data/{uid}
    // Esto garantiza que los datos no se pierden aunque localStorage esté vacío
    try {
      await loadRichDataForCurrentAndUsers();
    } catch (_) {}

    _attachListeners();
    _initialized = true;
  }

  void _attachListeners() {
    ExerciseStore.instance.addListener(_scheduleSave);
    WorkoutRoutineStore.instance.addListener(_scheduleSave);
    UserStore.instance.addListener(_scheduleSave);
    _attachRealtimeListeners();
  }

  void _attachRealtimeListeners() {
    _exercisesSub?.cancel();
    _routinesSub?.cancel();
    _usersSub?.cancel();
    _richDataSub?.cancel();

    // Exercises y routines: todos los roles reciben cambios en tiempo real
    _exercisesSub = _db
        .collection('app_state')
        .doc('exercises')
        .snapshots()
        .listen(_onExercisesSnapshot);
    _routinesSub = _db
        .collection('app_state')
        .doc('routines')
        .snapshots()
        .listen(_onRoutinesSnapshot);

    // Lista de usuarios: solo admin y trainer
    final role = UserStore.instance.currentUser.role;
    if (role == AppUserRole.admin || role == AppUserRole.trainer) {
      _usersSub = _db
          .collection('app_state')
          .doc('users')
          .snapshots()
          .listen(_onUsersSnapshot);
    }

    // Datos ricos del usuario actual: todos los roles
    final uid = UserStore.instance.currentUser.id;
    if (uid.isNotEmpty) {
      _richDataSub = _db
          .collection('user_rich_data')
          .doc(uid)
          .snapshots()
          .listen(_onRichDataSnapshot);
    }
  }

  /// Cancela todos los listeners en tiempo real. Llamar cuando el usuario
  /// cierra sesión para no recibir actualizaciones de otra cuenta.
  void cancelRealtimeListeners() {
    _exercisesSub?.cancel();
    _routinesSub?.cancel();
    _usersSub?.cancel();
    _richDataSub?.cancel();
    _exercisesSub = null;
    _routinesSub = null;
    _usersSub = null;
    _richDataSub = null;
  }

  /// Reconecta todos los listeners en tiempo real con el usuario actual.
  /// Llamar tras login para que el usuario reciba cambios en vivo.
  void reattachListeners() {
    _attachRealtimeListeners();
  }

  void _onExercisesSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || _applyingRemote) return;
    final data = snap.data();
    if (data == null) return;
    final items = _listMap(data['items']).map(_exerciseFromMap).toList();
    if (items.isEmpty) return;
    _applyingRemote = true;
    try {
      ExerciseStore.instance.replaceAll(items);
    } finally {
      _applyingRemote = false;
    }
  }

  void _onRoutinesSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || _applyingRemote) return;
    final data = snap.data();
    if (data == null) return;
    final items = _listMap(data['items']).map(_routineFromMap).toList();
    if (items.isEmpty) return;
    _applyingRemote = true;
    try {
      WorkoutRoutineStore.instance.replaceAll(items);
    } finally {
      _applyingRemote = false;
    }
  }

  void _onUsersSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || _applyingRemote) return;
    final data = snap.data();
    if (data == null) return;
    final users = _listMap(data['items']).map(_appUserFromMap).toList();
    final questionnaireTemplate = _listMap(data['questionnaireTemplate'])
        .map(_questionnaireQuestionFromMap)
        .toList();
    if (users.isEmpty) return;
    _applyingRemote = true;
    try {
      UserStore.instance.replaceAllFromCloud(
        users: users,
        questionnaireTemplate: questionnaireTemplate,
      );
    } finally {
      _applyingRemote = false;
    }
  }

  void _onRichDataSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || _applyingRemote) return;
    final data = snap.data();
    if (data == null) return;
    final uid = UserStore.instance.currentUser.id;
    if (uid.isEmpty) return;
    final fromCloud = _appUserFromMap({...data, 'id': uid});
    final existingIndex =
        UserStore.instance.users.indexWhere((u) => u.id == uid);
    if (existingIndex < 0) return;
    final existing = UserStore.instance.users[existingIndex];
    final merged = existing.copyWith(
      completedWorkouts: fromCloud.completedWorkouts.isNotEmpty
          ? fromCloud.completedWorkouts
          : null,
      evolutionTests: fromCloud.evolutionTests.isNotEmpty
          ? fromCloud.evolutionTests
          : null,
      trackingHistory: fromCloud.trackingHistory.isNotEmpty
          ? fromCloud.trackingHistory
          : null,
      exerciseWeightLogs: fromCloud.exerciseWeightLogs.isNotEmpty
          ? fromCloud.exerciseWeightLogs
          : null,
      scheduledRoutines: fromCloud.scheduledRoutines.isNotEmpty
          ? fromCloud.scheduledRoutines
          : null,
    );
    _applyingRemote = true;
    try {
      UserStore.instance.updateUserInPlace(merged);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _loadOrSeed() async {
    final exercisesRef = _db.collection('app_state').doc('exercises');
    final routinesRef = _db.collection('app_state').doc('routines');
    final usersRef = _db.collection('app_state').doc('users');

    final snapshots = await Future.wait([
      exercisesRef.get(),
      routinesRef.get(),
      usersRef.get(),
    ]);

    final exercisesSnap = snapshots[0];
    final routinesSnap = snapshots[1];
    final usersSnap = snapshots[2];

    final hasRemoteState =
        exercisesSnap.exists && routinesSnap.exists && usersSnap.exists;
    if (!hasRemoteState) {
      await _saveAll();
      return;
    }

    // Comparar timestamps: si caché local es más reciente que Firestore,
    // significa que hubo un save pendiente que no llegó a Firestore (p.ej.
    // la pestaña se cerró antes de que la escritura terminara).  En ese
    // caso conservamos los datos locales y los empujamos a Firestore.
    final prefs = await SharedPreferences.getInstance();
    final localTs = prefs.getInt(_kCacheLocalUpdatedAt) ?? 0;
    final remoteTs = (() {
      final t = exercisesSnap.data()?['updatedAt'];
      if (t is int) return t;
      if (t is num) return t.toInt();
      return 0;
    })();

    final role = UserStore.instance.currentUser.role;
    if (localTs > remoteTs &&
        (role == AppUserRole.admin || role == AppUserRole.trainer)) {
      // Datos locales son más recientes → los empujamos a Firestore y listo.
      await _saveAll();
      return;
    }

    final exercisesData = exercisesSnap.data();
    final routinesData = routinesSnap.data();
    final usersData = usersSnap.data();

    final exerciseItems = _listMap(
      exercisesData?['items'],
    ).map(_exerciseFromMap).toList();

    final routineItems = _listMap(
      routinesData?['items'],
    ).map(_routineFromMap).toList();

    final userItems = _listMap(
      usersData?['items'],
    ).map(_appUserFromMap).toList();

    final questionnaireTemplate = _listMap(
      usersData?['questionnaireTemplate'],
    ).map(_questionnaireQuestionFromMap).toList();

    _applyingRemote = true;
    try {
      if (exerciseItems.isNotEmpty) {
        ExerciseStore.instance.replaceAll(exerciseItems);
      }
      if (routineItems.isNotEmpty) {
        WorkoutRoutineStore.instance.replaceAll(routineItems);
      }
      if (userItems.isNotEmpty) {
        UserStore.instance.replaceAllFromCloud(
          users: userItems,
          questionnaireTemplate: questionnaireTemplate,
        );
      }
    } finally {
      _applyingRemote = false;
    }
  }

  void _scheduleSave() {
    if (_applyingRemote) return;
    _saveQueued = true;
    unawaited(_flushSaveQueue());
  }

  Future<void> _flushSaveQueue() async {
    if (_saveInFlight) return;
    _saveInFlight = true;
    try {
      while (_saveQueued) {
        _saveQueued = false;
        await _saveAll();
      }
    } finally {
      _saveInFlight = false;
    }
  }

  /// Guarda inmediatamente sin esperar el debounce. Útil tras operaciones
  /// destructivas (eliminar usuario) para que Firestore quede actualizado
  /// antes de un posible reload.
  Future<void> saveNow() => _saveAll();

  Future<void> _saveAll() async {
    final role = UserStore.instance.currentUser.role;
    // Caché local: incluye binarios (base64) para restaurar sin internet.
    // Los usuarios normales NO sobreescriben la lista de usuarios en caché
    // para evitar que corrompan la lista completa que gestionó el admin.
    final fullPayload = _buildPayload(includeBinary: true);
    if (role == AppUserRole.admin || role == AppUserRole.trainer) {
      await _saveToLocalCache(fullPayload, mode: 'full');
    } else {
      // Solo guardar ejercicios y rutinas en caché local, preservar usuarios
      await _saveToLocalCachePartial(fullPayload);
    }
    // Cloud: NUNCA incrustar binarios (límite 1MB por doc en Firestore)
    final cloudPayload = _buildPayload(includeBinary: false);
    if (role == AppUserRole.admin) {
      // Admin guarda todo: ejercicios, rutinas y usuarios
      await _saveToCloud(cloudPayload, mode: 'full');
      // También actualiza user_rich_data de cada usuario para que reciban
      // en tiempo real cambios como rutinas asignadas.
      await _saveAllUsersRichData();
    } else if (role == AppUserRole.trainer) {
      // Trainer guarda ejercicios y rutinas (compartidos)
      await _saveExercisesAndRoutinesToCloud(cloudPayload);
      // También actualiza user_rich_data de sus usuarios asignados
      await _saveAllUsersRichData();
    }
    // Todos los roles guardan sus propios datos ricos en user_rich_data/{uid}
    await _saveCurrentUserRichData();
  }

  /// Guarda los datos ricos del usuario actual en user_rich_data/{uid}.
  /// Esto garantiza que entrenos, evolución, seguimiento y progreso
  /// persisten en Firestore para cualquier rol (admin, trainer, user).
  Future<void> _saveCurrentUserRichData() async {
    final user = UserStore.instance.currentUser;
    if (user.id.isEmpty) return;
    try {
      final userMap = _appUserToMap(user, includeBinary: false);
      await _db.collection('user_rich_data').doc(user.id).set({
        ...userMap,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e, s) {
      _log('Error guardando user_rich_data/${user.id}', e, s);
    }
  }

  /// Cuando el admin/trainer asigna rutinas u otros datos ricos a los usuarios,
  /// los guarda en user_rich_data/{uid} para que cada usuario lo reciba
  /// en tiempo real a través de su listener personal.
  Future<void> _saveAllUsersRichData() async {
    final currentId = UserStore.instance.currentUser.id;
    final users = UserStore.instance.users
        .where((u) => u.id != currentId)
        .toList();
    for (final user in users) {
      if (user.id.isEmpty) continue;
      try {
        final userMap = _appUserToMap(user, includeBinary: false);
        await _db.collection('user_rich_data').doc(user.id).set({
          ...userMap,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      } catch (e, s) {
        _log('Error guardando user_rich_data/${user.id}', e, s);
      }
    }
  }

  /// Carga los datos ricos de un usuario desde user_rich_data/{uid}
  /// y los fusiona con los datos que ya hay en memoria.
  Future<void> _mergeUserRichDataFromCloud(String uid) async {
    if (uid.isEmpty) return;
    try {
      final doc = await _db.collection('user_rich_data').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final fromCloud = _appUserFromMap({...data, 'id': uid});
      final existingIndex = UserStore.instance.users.indexWhere((u) => u.id == uid);
      final existing = existingIndex >= 0
          ? UserStore.instance.users[existingIndex]
          : fromCloud;

      // Timestamp: si los datos locales son más recientes, no sobrescribir
      final cloudTs = data['savedAt'] is int
          ? data['savedAt'] as int
          : (data['savedAt'] is num ? (data['savedAt'] as num).toInt() : 0);
      final prefs = await SharedPreferences.getInstance();
      final localTs = prefs.getInt(_kCacheLocalUpdatedAt) ?? 0;
      if (localTs > cloudTs && existing.completedWorkouts.isNotEmpty) return;

      final merged = existing.copyWith(
        completedWorkouts: fromCloud.completedWorkouts.isNotEmpty
            ? fromCloud.completedWorkouts
            : null,
        evolutionTests: fromCloud.evolutionTests.isNotEmpty
            ? fromCloud.evolutionTests
            : null,
        trackingHistory: fromCloud.trackingHistory.isNotEmpty
            ? fromCloud.trackingHistory
            : null,
        exerciseWeightLogs: fromCloud.exerciseWeightLogs.isNotEmpty
            ? fromCloud.exerciseWeightLogs
            : null,
        scheduledRoutines: fromCloud.scheduledRoutines.isNotEmpty
            ? fromCloud.scheduledRoutines
            : null,
        questionnaireQuestions: fromCloud.questionnaireQuestions.isNotEmpty
            ? fromCloud.questionnaireQuestions
            : null,
        questionnaireResponses: fromCloud.questionnaireResponses.isNotEmpty
            ? fromCloud.questionnaireResponses
            : null,
        questionnaireCompletedAt:
            fromCloud.questionnaireCompletedAt ?? existing.questionnaireCompletedAt,
      );

      _applyingRemote = true;
      try {
        UserStore.instance.updateUserInPlace(merged);
      } finally {
        _applyingRemote = false;
      }
    } catch (e, s) {
      _log('Error cargando user_rich_data/$uid', e, s);
    }
  }

  /// Carga datos ricos para el usuario actual y, si es trainer/admin,
  /// también para sus usuarios asignados.
  Future<void> loadRichDataForCurrentAndUsers() async {
    final currentId = UserStore.instance.currentUser.id;
    if (currentId.isEmpty) return;

    // Cargar datos propios
    await _mergeUserRichDataFromCloud(currentId);

    // Para admin y trainer, cargar también los datos de sus usuarios
    final role = UserStore.instance.currentUser.role;
    if (role == AppUserRole.admin || role == AppUserRole.trainer) {
      final usersToLoad = UserStore.instance.users
          .where((u) => u.id != currentId && u.trainerId == currentId)
          .toList();
      for (final u in usersToLoad) {
        await _mergeUserRichDataFromCloud(u.id);
      }
    }
  }

  Map<String, List<Map<String, dynamic>>> _buildPayload({
    required bool includeBinary,
  }) {
    final exercises = ExerciseStore.instance.exercises
        .map((item) => _exerciseToMap(item, includeBinary: includeBinary))
        .toList();
    final routines = WorkoutRoutineStore.instance.routines
        .map(_routineToMap)
        .toList();
    final users = UserStore.instance.users
        .map((user) => _appUserToMap(user, includeBinary: includeBinary))
        .toList();
    final questionnaireTemplate = UserStore.instance
        .questionnaireTemplateQuestions()
        .map(_questionnaireQuestionToMap)
        .toList();

    return {
      'exercises': exercises,
      'routines': routines,
      'users': users,
      'questionnaireTemplate': questionnaireTemplate,
    };
  }

  Future<bool> _saveToLocalCache(
    Map<String, List<Map<String, dynamic>>> payload, {
    required String mode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheExercises, jsonEncode(payload['exercises']));
      await prefs.setString(_kCacheRoutines, jsonEncode(payload['routines']));
      await prefs.setString(_kCacheUsers, jsonEncode(payload['users']));
      await prefs.setString(
        _kCacheQuestionnaireTemplate,
        jsonEncode(payload['questionnaireTemplate']),
      );
      // Guardar timestamp del momento del save local
      await prefs.setInt(
        _kCacheLocalUpdatedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (error, stackTrace) {
      _log('Error guardando cache local ($mode)', error, stackTrace);
      return false;
    }
  }

  /// Guarda solo ejercicios y rutinas en caché local, sin tocar la lista de
  /// usuarios ni el timestamp de comparación con Firestore.
  /// Usado para usuarios normales para no corromper la lista de usuarios del admin.
  Future<bool> _saveToLocalCachePartial(
    Map<String, List<Map<String, dynamic>>> payload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheExercises, jsonEncode(payload['exercises']));
      await prefs.setString(_kCacheRoutines, jsonEncode(payload['routines']));
      // NO se toca _kCacheUsers ni _kCacheLocalUpdatedAt
      return true;
    } catch (error, stackTrace) {
      _log('Error guardando cache local parcial', error, stackTrace);
      return false;
    }
  }

  Future<bool> _saveToCloud(
    Map<String, List<Map<String, dynamic>>> payload, {
    required String mode,
  }) async {
    final batch = _db.batch();
    batch.set(_db.collection('app_state').doc('exercises'), {
      'items': payload['exercises'],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    batch.set(_db.collection('app_state').doc('routines'), {
      'items': payload['routines'],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    batch.set(_db.collection('app_state').doc('users'), {
      'items': payload['users'],
      'questionnaireTemplate': payload['questionnaireTemplate'],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    try {
      await batch.commit();
      return true;
    } catch (error, stackTrace) {
      _log('Error guardando Firestore ($mode)', error, stackTrace);
      return false;
    }
  }

  /// Solo guarda ejercicios y rutinas (para trainers).
  /// No toca app_state/users para no sobreescribir la lista completa.
  Future<bool> _saveExercisesAndRoutinesToCloud(
    Map<String, List<Map<String, dynamic>>> payload,
  ) async {
    final batch = _db.batch();
    batch.set(_db.collection('app_state').doc('exercises'), {
      'items': payload['exercises'],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    batch.set(_db.collection('app_state').doc('routines'), {
      'items': payload['routines'],
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      await batch.commit();
      return true;
    } catch (error, stackTrace) {
      _log('Error guardando ejercicios/rutinas Firestore (trainer)', error, stackTrace);
      return false;
    }
  }

  Future<void> _loadFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final exercisesRaw = prefs.getString(_kCacheExercises);
    final routinesRaw = prefs.getString(_kCacheRoutines);
    final usersRaw = prefs.getString(_kCacheUsers);
    final questionnaireRaw = prefs.getString(_kCacheQuestionnaireTemplate);

    if (exercisesRaw == null && routinesRaw == null && usersRaw == null) return;

    final exercises = _decodeListMap(
      exercisesRaw,
    ).map(_exerciseFromMap).toList();
    final routines = _decodeListMap(routinesRaw).map(_routineFromMap).toList();
    final users = _decodeListMap(usersRaw).map(_appUserFromMap).toList();
    final questionnaireTemplate = _decodeListMap(
      questionnaireRaw,
    ).map(_questionnaireQuestionFromMap).toList();

    _applyingRemote = true;
    try {
      if (exercises.isNotEmpty) {
        ExerciseStore.instance.replaceAll(exercises);
      }
      if (routines.isNotEmpty) {
        WorkoutRoutineStore.instance.replaceAll(routines);
      }
      if (users.isNotEmpty) {
        UserStore.instance.replaceAllFromCloud(
          users: users,
          questionnaireTemplate: questionnaireTemplate,
        );
      }
    } finally {
      _applyingRemote = false;
    }
  }

  List<Map<String, dynamic>> _decodeListMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      return _listMap(data);
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _listMap(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((item) {
      return item.map((key, val) => MapEntry(key.toString(), val));
    }).toList();
  }

  Map<String, dynamic> _exerciseToMap(
    ExerciseEntry item, {
    required bool includeBinary,
  }) {
    final shouldEmbedImage =
        includeBinary &&
        item.imageUrl.trim().isEmpty &&
        item.imageBytes != null;
    return {
      'name': item.name,
      'category': item.category,
      'equipment': item.equipment,
      'level': item.level,
      'description': item.description,
      'muscles': item.muscles,
      'videoUrl': item.videoUrl,
      'imageUrl': item.imageUrl,
      'imageName': item.imageName,
      'tips': item.tips,
      'imageBase64': shouldEmbedImage ? base64Encode(item.imageBytes!) : null,
    };
  }

  ExerciseEntry _exerciseFromMap(Map<String, dynamic> map) {
    return ExerciseEntry(
      name: (map['name'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      equipment: (map['equipment'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      level: (map['level'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      muscles: (map['muscles'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      videoUrl: (map['videoUrl'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      imageName: (map['imageName'] ?? '').toString(),
      tips: (map['tips'] ?? '').toString(),
      imageBytes: _bytesFromBase64(map['imageBase64']),
    );
  }

  Map<String, dynamic> _routineToMap(WorkoutRoutine routine) {
    return {
      'name': routine.name,
      'description': routine.description,
      'kind': routine.kind.name,
      'rounds': routine.rounds,
      'exercises': routine.exercises.map(_routineExerciseToMap).toList(),
    };
  }

  WorkoutRoutine _routineFromMap(Map<String, dynamic> map) {
    return WorkoutRoutine(
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      kind: _routineKindFromName((map['kind'] ?? '').toString()),
      rounds: _toInt(map['rounds']) ?? 1,
      exercises: _listMap(
        map['exercises'],
      ).map(_routineExerciseFromMap).toList(),
    );
  }

  Map<String, dynamic> _routineExerciseToMap(WorkoutRoutineExercise exercise) {
    return {
      'name': exercise.name,
      'mode': exercise.mode.name,
      'durationSeconds': exercise.durationSeconds,
      'restSeconds': exercise.restSeconds,
      'sets': exercise.sets,
      'reps': exercise.reps,
      'weightKg': exercise.weightKg,
      'showWeightField': exercise.showWeightField,
    };
  }

  WorkoutRoutineExercise _routineExerciseFromMap(Map<String, dynamic> map) {
    return WorkoutRoutineExercise(
      name: (map['name'] ?? '').toString(),
      mode: _exerciseModeFromName((map['mode'] ?? '').toString()),
      durationSeconds: _toInt(map['durationSeconds']) ?? 180,
      restSeconds: _toInt(map['restSeconds']) ?? 20,
      sets: _toInt(map['sets']),
      reps: _toInt(map['reps']),
      weightKg: _toDouble(map['weightKg']),
      showWeightField: map['showWeightField'] == true,
    );
  }

  Map<String, dynamic> _appUserToMap(
    AppUserData user, {
    required bool includeBinary,
  }) {
    final shouldEmbedProfilePhoto =
        includeBinary &&
        user.photoUrl.trim().isEmpty &&
        user.photoBytes != null;
    return {
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'role': user.role.name,
      'age': user.age,
      'level': user.level,
      'weightKg': user.weightKg,
      'heightCm': user.heightCm,
      'objectives': user.objectives,
      'photoUrl': user.photoUrl,
      'photoBase64': shouldEmbedProfilePhoto
          ? base64Encode(user.photoBytes!)
          : null,
      'trainerId': user.trainerId,
      'trainerCode': user.trainerCode,
      'scheduledRoutines': user.scheduledRoutines
          .map(_scheduledRoutineToMap)
          .toList(),
      'completedWorkouts': user.completedWorkouts
          .map(_completionToMap)
          .toList(),
      'trackingHistory': user.trackingHistory
          .map(
            (item) => _trackingEntryToMap(item, includeBinary: includeBinary),
          )
          .toList(),
      'exerciseWeightLogs': user.exerciseWeightLogs
          .map(_weightLogToMap)
          .toList(),
      'evolutionTests': user.evolutionTests
          .map(
            (item) => _evolutionTestToMap(item, includeBinary: includeBinary),
          )
          .toList(),
      'questionnaireQuestions': user.questionnaireQuestions
          .map(_questionnaireQuestionToMap)
          .toList(),
      'questionnaireResponses': user.questionnaireResponses
          .map(_questionnaireResponseToMap)
          .toList(),
      'questionnaireCompletedAt': _millis(user.questionnaireCompletedAt),
      'createdAt': _millis(user.createdAt),
    };
  }

  AppUserData _appUserFromMap(Map<String, dynamic> map) {
    return AppUserData(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      role: _roleFromName((map['role'] ?? '').toString()),
      age: _toInt(map['age']),
      level: map['level']?.toString(),
      weightKg: _toDouble(map['weightKg']),
      heightCm: _toInt(map['heightCm']),
      objectives: (map['objectives'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      photoUrl: (map['photoUrl'] ?? '').toString(),
      photoBytes: _bytesFromBase64(map['photoBase64']),
      trainerId: (() {
        final v = map['trainerId']?.toString();
        if (v == null) return null;
        final t = v.trim();
        return t.isEmpty ? null : t;
      }()),
      trainerCode: map['trainerCode']?.toString(),
      scheduledRoutines: _listMap(
        map['scheduledRoutines'],
      ).map(_scheduledRoutineFromMap).toList(),
      completedWorkouts: _listMap(
        map['completedWorkouts'],
      ).map(_completionFromMap).toList(),
      trackingHistory: _listMap(
        map['trackingHistory'],
      ).map(_trackingEntryFromMap).toList(),
      exerciseWeightLogs: _listMap(
        map['exerciseWeightLogs'],
      ).map(_weightLogFromMap).toList(),
      evolutionTests: _listMap(
        map['evolutionTests'],
      ).map(_evolutionTestFromMap).toList(),
      questionnaireQuestions: _listMap(
        map['questionnaireQuestions'],
      ).map(_questionnaireQuestionFromMap).toList(),
      questionnaireResponses: _listMap(
        map['questionnaireResponses'],
      ).map(_questionnaireResponseFromMap).toList(),
      questionnaireCompletedAt: _dateFromMillis(
        map['questionnaireCompletedAt'],
      ),
      createdAt: _dateFromMillis(map['createdAt']),
    );
  }

  Map<String, dynamic> _scheduledRoutineToMap(ScheduledRoutineAssignment item) {
    return {'routineName': item.routineName, 'date': _millis(item.date)};
  }

  ScheduledRoutineAssignment _scheduledRoutineFromMap(
    Map<String, dynamic> map,
  ) {
    return ScheduledRoutineAssignment(
      routineName: (map['routineName'] ?? '').toString(),
      date: _dateFromMillis(map['date']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> _completionToMap(WorkoutCompletion item) {
    return {
      'routineName': item.routineName,
      'date': _millis(item.date),
      'totalSeconds': item.totalSeconds,
      'rating': item.rating,
    };
  }

  WorkoutCompletion _completionFromMap(Map<String, dynamic> map) {
    return WorkoutCompletion(
      routineName: (map['routineName'] ?? '').toString(),
      date: _dateFromMillis(map['date']) ?? DateTime.now(),
      totalSeconds: _toInt(map['totalSeconds']) ?? 0,
      rating: _toInt(map['rating']) ?? 5,
    );
  }

  Map<String, dynamic> _trackingEntryToMap(
    UserTrackingEntry item, {
    required bool includeBinary,
  }) {
    final shouldEmbedTrackingPhoto =
        includeBinary &&
        item.photoUrl.trim().isEmpty &&
        item.photoBytes != null;
    return {
      'date': _millis(item.date),
      'photoUrl': item.photoUrl,
      'photoBase64': shouldEmbedTrackingPhoto
          ? base64Encode(item.photoBytes!)
          : null,
      'weightKg': item.weightKg,
      'waistCm': item.waistCm,
      'hipsCm': item.hipsCm,
      'armsCm': item.armsCm,
      'thighsCm': item.thighsCm,
      'calvesCm': item.calvesCm,
      'forearmCm': item.forearmCm,
      'neckCm': item.neckCm,
      'chestCm': item.chestCm,
      'notes': item.notes,
    };
  }

  UserTrackingEntry _trackingEntryFromMap(Map<String, dynamic> map) {
    return UserTrackingEntry(
      date: _dateFromMillis(map['date']) ?? DateTime.now(),
      photoUrl: (map['photoUrl'] ?? '').toString(),
      photoBytes: _bytesFromBase64(map['photoBase64']),
      weightKg: _toDouble(map['weightKg']),
      waistCm: _toDouble(map['waistCm']),
      hipsCm: _toDouble(map['hipsCm']),
      armsCm: _toDouble(map['armsCm']),
      thighsCm: _toDouble(map['thighsCm']),
      calvesCm: _toDouble(map['calvesCm']),
      forearmCm: _toDouble(map['forearmCm']),
      neckCm: _toDouble(map['neckCm']),
      chestCm: _toDouble(map['chestCm']),
      notes: (map['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> _weightLogToMap(ExerciseWeightLogEntry item) {
    return {
      'exerciseName': item.exerciseName,
      'date': _millis(item.date),
      'weightKg': item.weightKg,
    };
  }

  ExerciseWeightLogEntry _weightLogFromMap(Map<String, dynamic> map) {
    return ExerciseWeightLogEntry(
      exerciseName: (map['exerciseName'] ?? '').toString(),
      date: _dateFromMillis(map['date']) ?? DateTime.now(),
      weightKg: _toDouble(map['weightKg']) ?? 0,
    );
  }

  Map<String, dynamic> _evolutionTestToMap(
    EvolutionTest item, {
    required bool includeBinary,
  }) {
    return {
      'id': item.id,
      'title': item.title,
      'description': item.description,
      'createdAt': _millis(item.createdAt),
      'createdByAdmin': item.createdByAdmin,
      'entries': item.entries
          .map(
            (entry) =>
                _evolutionEntryToMap(entry, includeBinary: includeBinary),
          )
          .toList(),
    };
  }

  EvolutionTest _evolutionTestFromMap(Map<String, dynamic> map) {
    return EvolutionTest(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      createdAt: _dateFromMillis(map['createdAt']) ?? DateTime.now(),
      createdByAdmin: map['createdByAdmin'] == true,
      entries: _listMap(map['entries']).map(_evolutionEntryFromMap).toList(),
    );
  }

  Map<String, dynamic> _evolutionEntryToMap(
    EvolutionTestEntry item, {
    required bool includeBinary,
  }) {
    final shouldEmbedEvaluationPhoto =
        includeBinary &&
        item.imageUrl.trim().isEmpty &&
        item.imageBytes != null;
    return {
      'id': item.id,
      'date': _millis(item.date),
      'note': item.note,
      'imageUrl': item.imageUrl,
      'imageName': item.imageName,
      'imageBase64': shouldEmbedEvaluationPhoto
          ? base64Encode(item.imageBytes!)
          : null,
    };
  }

  EvolutionTestEntry _evolutionEntryFromMap(Map<String, dynamic> map) {
    return EvolutionTestEntry(
      id: (map['id'] ?? '').toString(),
      date: _dateFromMillis(map['date']) ?? DateTime.now(),
      note: (map['note'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      imageName: (map['imageName'] ?? '').toString(),
      imageBytes: _bytesFromBase64(map['imageBase64']),
    );
  }

  Map<String, dynamic> _questionnaireQuestionToMap(QuestionnaireQuestion item) {
    return {'id': item.id, 'text': item.text};
  }

  QuestionnaireQuestion _questionnaireQuestionFromMap(
    Map<String, dynamic> map,
  ) {
    return QuestionnaireQuestion(
      id: (map['id'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
    );
  }

  Map<String, dynamic> _questionnaireResponseToMap(QuestionnaireResponse item) {
    return {'questionId': item.questionId, 'answer': item.answer};
  }

  QuestionnaireResponse _questionnaireResponseFromMap(
    Map<String, dynamic> map,
  ) {
    return QuestionnaireResponse(
      questionId: (map['questionId'] ?? '').toString(),
      answer: (map['answer'] ?? '').toString(),
    );
  }

  int? _millis(DateTime? value) => value?.millisecondsSinceEpoch;

  DateTime? _dateFromMillis(dynamic value) {
    final millis = _toInt(value);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

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

  Uint8List? _bytesFromBase64(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  AppUserRole _roleFromName(String name) {
    switch (name) {
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

  WorkoutRoutineKind _routineKindFromName(String name) {
    switch (name) {
      case 'timed':
        return WorkoutRoutineKind.timed;
      case 'reps':
        return WorkoutRoutineKind.reps;
      case 'circuit':
        return WorkoutRoutineKind.circuit;
      case 'mixed':
      default:
        return WorkoutRoutineKind.mixed;
    }
  }

  WorkoutExerciseMode _exerciseModeFromName(String name) {
    switch (name) {
      case 'reps':
        return WorkoutExerciseMode.reps;
      case 'timed':
      default:
        return WorkoutExerciseMode.timed;
    }
  }

  void _log(String message, Object error, StackTrace stackTrace) {
    debugPrint('[CloudSyncService] $message: $error');
    if (kDebugMode) {
      debugPrint(stackTrace.toString());
    }
  }
}
