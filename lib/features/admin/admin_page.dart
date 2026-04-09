import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:image_picker/image_picker.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/cloud_sync_service.dart';
import '../../data/cloudinary_service.dart';
import '../../data/exercise_store.dart';
import '../../data/user_store.dart';
import '../../data/workout_routine_store.dart';
import '../../theme/app_theme.dart';
import '../home/evolution_tab.dart';
import '../shared/questionnaire_editor_dialog.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const List<String> _kCategories = [
  'Pecho',
  'Espalda',
  'Piernas',
  'Brazos',
  'Abdomen',
  'Cardio',
  'Funcional',
];

const List<String> _kLevels = ['Principiante', 'Intermedio', 'Avanzado'];

const List<String> _kMuscles = [
  'Pectorales',
  'Deltoides',
  'Biceps',
  'Triceps',
  'Dorsales',
  'Trapecio',
  'Cuadriceps',
  'Isquiotibiales',
  'Gluteos',
  'Gemelos',
  'Abdominales',
  'Core',
];

const List<String> _kEquipmentForm = [
  'Peso corporal',
  'Mancuernas',
  'Barra',
  'Maquina',
  'Polea',
  'Banda elastica',
  'Kettlebell',
  'TRX',
  'Barra dominadas',
  'Discos',
  'Cuerda para polea',
  'Fitball',
  'Sliders',
  'Banco',
];

const Map<String, ({Color bg, Color fg})> _kCatColors = {
  'Pecho': (bg: Color(0xFFFFD9D1), fg: Color(0xFF7F1D1D)),
  'Espalda': (bg: Color(0xFFD6E8FF), fg: Color(0xFF1E3A8A)),
  'Piernas': (bg: Color(0xFFEDE1FF), fg: Color(0xFF5B21B6)),
  'Hombros': (bg: Color(0xFFFFE5CF), fg: Color(0xFF9A3412)),
  'Brazos': (bg: Color(0xFFFFE0EF), fg: Color(0xFF9F1239)),
  'Abdomen': (bg: Color(0xFFD8F3EE), fg: Color(0xFF115E59)),
  'Cardio': (bg: Color(0xFFFFD9DC), fg: Color(0xFF991B1B)),
  'Funcional': (bg: Color(0xFFFEF3C7), fg: Color(0xFF854D0E)),
};

const List<String> _kWeekLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

const List<String> _kMonthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

enum _RoutineSpecType { time, setsReps }

enum _RoutineTrainingType { timed, reps, mixed, circuit }

class _RoutineExerciseSpec {
  _RoutineExerciseSpec({
    required this.exercise,
    required this.type,
    this.workSeconds,
    this.sets,
    this.reps,
    this.weightKg,
    this.restSeconds,
    this.showWeightField = false,
  });

  final ExerciseEntry exercise;
  final _RoutineSpecType type;
  final int? workSeconds;
  final int? sets;
  final int? reps;
  final double? weightKg;
  final int? restSeconds;
  final bool showWeightField;

  int? get durationSeconds => workSeconds;

  _RoutineExerciseSpec copyWith({
    ExerciseEntry? exercise,
    _RoutineSpecType? type,
    int? workSeconds,
    int? sets,
    int? reps,
    double? weightKg,
    int? restSeconds,
    bool? showWeightField,
  }) {
    return _RoutineExerciseSpec(
      exercise: exercise ?? this.exercise,
      type: type ?? this.type,
      workSeconds: workSeconds ?? this.workSeconds,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      weightKg: weightKg ?? this.weightKg,
      restSeconds: restSeconds ?? this.restSeconds,
      showWeightField: showWeightField ?? this.showWeightField,
    );
  }
}

class _RoutineData {
  _RoutineData({
    required this.name,
    required this.description,
    required this.exercises,
    this.trainingType = _RoutineTrainingType.mixed,
    this.rounds = 1,
  });

  final String name;
  final String description;
  final List<_RoutineExerciseSpec> exercises;
  final _RoutineTrainingType trainingType;
  final int rounds;
}

enum _UserQuickAction {
  assignRoutine,
  viewProfile,
  viewHistory,
  viewProgress,
  viewEvolution,
  viewTracking,
  changeRole,
}

class _AdminTabs extends StatelessWidget {
  const _AdminTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 24),
        itemBuilder: (context, index) {
          final isActive = index == selectedIndex;
          return TextButton(
            onPressed: () => onSelected(index),
            style: TextButton.styleFrom(
              foregroundColor: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              textStyle: TextStyle(
                fontSize: 18,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            child: Text(tabs[index]),
          );
        },
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static int _lastSelectedTab = 0;
  int _selectedTab = _lastSelectedTab;
  List<_RoutineData> _routines = <_RoutineData>[];
  late final TextEditingController _searchCtrl;
  String _searchQuery = '';

  bool _loadingCodes = false;
  String _adminUserCode = '';
  String _trainerUpgradeCode = '';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _trainerCodeSub;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    if (_selectedTab < 0 || _selectedTab >= _tabs.length) {
      _selectedTab = 0;
      _lastSelectedTab = 0;
    }
    if (UserStore.instance.currentUser.role == AppUserRole.admin ||
        UserStore.instance.currentUser.role == AppUserRole.trainer) {
      unawaited(() async {
        await UserStore.instance.loadAllUsersFromFirestore();
        // Marcar en Firestore a los usuarios sin trainer como 'sinclave'
        await UserStore.instance.setSinclaveForOrphansOnFirestore();
        await CloudSyncService.instance.loadRichDataForCurrentAndUsers();
      }());
    }
    // Inicializar _routines desde el store (datos ya cargados desde la nube).
    // Solo usar rutinas de muestra si el store está vacío.
    _routines = _routinesFromStore();
    if (_routines.isEmpty) {
      _routines = _buildSampleRoutines();
      if (_routines.isEmpty) {
        ExerciseStore.instance.addListener(_onExercisesReady);
      } else {
        _syncWorkoutRoutineStore();
      }
    }
    // Escuchar cambios del store (p.ej. cuando la nube actualiza rutinas)
    WorkoutRoutineStore.instance.addListener(_onStoreRoutinesChanged);
    if (UserStore.instance.currentUser.role == AppUserRole.admin) {
      _startTrainerCodeListener();
    }
  }

  /// Convierte WorkoutRoutine → _RoutineData para restaurar el estado local
  List<_RoutineData> _routinesFromStore() {
    final storeRoutines = WorkoutRoutineStore.instance.routines;
    if (storeRoutines.isEmpty) return <_RoutineData>[];
    final byName = {
      for (final e in ExerciseStore.instance.exercises) e.name: e,
    };
    return storeRoutines.map((r) {
      return _RoutineData(
        name: r.name,
        description: r.description,
        trainingType: switch (r.kind) {
          WorkoutRoutineKind.timed => _RoutineTrainingType.timed,
          WorkoutRoutineKind.reps => _RoutineTrainingType.reps,
          WorkoutRoutineKind.mixed => _RoutineTrainingType.mixed,
          WorkoutRoutineKind.circuit => _RoutineTrainingType.circuit,
        },
        rounds: r.rounds,
        exercises: r.exercises.map((ex) {
          final exercise = byName[ex.name] ??
              ExerciseEntry(
                name: ex.name,
                category: '',
                equipment: const [],
                level: '',
                description: '',
              );
          return _RoutineExerciseSpec(
            exercise: exercise,
            type: ex.mode == WorkoutExerciseMode.timed
                ? _RoutineSpecType.time
                : _RoutineSpecType.setsReps,
            workSeconds: ex.durationSeconds > 0 ? ex.durationSeconds : null,
            sets: ex.sets,
            reps: ex.reps,
            restSeconds: ex.restSeconds,
            weightKg: ex.weightKg,
            showWeightField: ex.showWeightField,
          );
        }).toList(),
      );
    }).toList();
  }

  void _onStoreRoutinesChanged() {
    final fromStore = _routinesFromStore();
    // Solo actualizar si el store tiene más rutinas de las que tenemos en local
    // (evita bucle: local→store→local)
    if (fromStore.length != _routines.length && mounted) {
      setState(() {
        _routines = fromStore;
      });
    }
  }

  void _onExercisesReady() {
    if (ExerciseStore.instance.exercises.isNotEmpty && _routines.isEmpty) {
      ExerciseStore.instance.removeListener(_onExercisesReady);
      setState(() {
        _routines = _buildSampleRoutines();
      });
      _syncWorkoutRoutineStore();
    }
  }

  @override
  void dispose() {
    ExerciseStore.instance.removeListener(_onExercisesReady);
    WorkoutRoutineStore.instance.removeListener(_onStoreRoutinesChanged);
    _trainerCodeSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startTrainerCodeListener() {
    _trainerCodeSub?.cancel();
    _trainerCodeSub = FirebaseFirestore.instance
        .collection('access_keys')
        .where('tipo', isEqualTo: 'trainer_upgrade')
        .snapshots()
        .listen((snap) {
      final available = snap.docs
          .where((doc) => (doc.data()['usado'] as bool?) != true)
          .map((doc) => doc.id)
          .where((id) => id.trim().isNotEmpty)
          .toList()
        ..sort();
      final next = available.isNotEmpty ? available.first : '';
      if (mounted && next != _trainerUpgradeCode) {
        setState(() => _trainerUpgradeCode = next);
      }
    });
  }

  void _setSelectedTab(int nextTab) {
    final bounded = nextTab.clamp(0, _tabs.length - 1);
    setState(() {
      _selectedTab = bounded;
      _lastSelectedTab = bounded;
    });
  }

  static const List<String> _tabs = [
    'Usuarios',
    'Rutinas',
    'Ejercicios',
  ];

  List<_RoutineData> _buildSampleRoutines() {
    final exercises = ExerciseStore.instance.exercises;
    if (exercises.isEmpty) return <_RoutineData>[];
    final byName = {for (final e in exercises) e.name: e};

    _RoutineExerciseSpec spec(String name) {
      final exercise = byName[name] ?? exercises.first;
      return _RoutineExerciseSpec(
        exercise: exercise,
        type: _RoutineSpecType.setsReps,
        sets: 4,
        reps: 10,
        restSeconds: 60,
      );
    }

    return [
      _RoutineData(
        name: 'Full Body Express',
        description:
            'Rutina corta para activar todo el cuerpo en 35-40 minutos.',
        exercises: [
          spec('Sentadilla'),
          spec('Flexiones'),
          spec('Remo con barra'),
        ],
        trainingType: _RoutineTrainingType.reps,
      ),
      _RoutineData(
        name: 'Push + Core',
        description: 'Empuje de torso con trabajo abdominal al final.',
        exercises: [
          spec('Press de banca'),
          spec('Press militar'),
          spec('Plancha'),
        ],
        trainingType: _RoutineTrainingType.reps,
      ),
    ];
  }

  void _syncWorkoutRoutineStore() {
    final converted = _routines.map((routine) {
      return WorkoutRoutine(
        name: routine.name,
        description: routine.description,
        kind: switch (routine.trainingType) {
          _RoutineTrainingType.timed => WorkoutRoutineKind.timed,
          _RoutineTrainingType.reps => WorkoutRoutineKind.reps,
          _RoutineTrainingType.mixed => WorkoutRoutineKind.mixed,
          _RoutineTrainingType.circuit => WorkoutRoutineKind.circuit,
        },
        rounds: routine.rounds,
        exercises: routine.exercises.map((spec) {
          final isTimed = spec.type == _RoutineSpecType.time;
          return WorkoutRoutineExercise(
            name: spec.exercise.name,
            mode: isTimed ? WorkoutExerciseMode.timed : WorkoutExerciseMode.reps,
            durationSeconds: isTimed ? (spec.workSeconds ?? 30) : 0,
            sets: isTimed ? (spec.sets ?? 1) : (spec.sets ?? 3),
            reps: isTimed ? null : (spec.reps ?? 10),
            restSeconds: spec.restSeconds ?? 60,
            weightKg: spec.weightKg,
            showWeightField: spec.showWeightField,
          );
        }).toList(),
      );
    }).toList();
    WorkoutRoutineStore.instance.replaceAll(converted);
  }

  Future<void> _addExerciseFromTab() async {
    final result = await _openExerciseForm();
    if (result == null || !mounted) return;
    ExerciseStore.instance.add(result);
    _setSelectedTab(2);
  }

  Future<ExerciseEntry?> _openExerciseForm({ExerciseEntry? existing}) {
    return showModalBottomSheet<ExerciseEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseFormSheet(existing: existing),
    );
  }

  Future<void> _createRoutineFromTab() async {
    final result = await showModalBottomSheet<_RoutineData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RoutineFormSheet(),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _routines.add(result);
        _syncWorkoutRoutineStore();
      });
      _setSelectedTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rutina "${result.name}" guardada'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<_RoutineData?> _createRoutineFromUserModal() async {
    final result = await showModalBottomSheet<_RoutineData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RoutineFormSheet(),
    );
    if (!mounted || result == null) return null;
    setState(() {
      _routines.add(result);
      _syncWorkoutRoutineStore();
    });
    return result;
  }

  Future<void> _editRoutine(int index) async {
    final result = await showModalBottomSheet<_RoutineData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoutineFormSheet(existing: _routines[index]),
    );

    if (!mounted || result == null) return;
    setState(() {
      _routines[index] = result;
      _syncWorkoutRoutineStore();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rutina "${result.name}" actualizada'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteRoutine(int index) {
    final name = _routines[index].name;
    setState(() {
      _routines.removeAt(index);
      _syncWorkoutRoutineStore();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rutina "$name" eliminada'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _changeUserRole(int index, AppUserRole newRole) async {
    final users = UserStore.instance.users;
    if (users[index].role == newRole) return;
    final action = newRole == AppUserRole.admin
        ? 'ADMIN'
        : newRole == AppUserRole.trainer
            ? 'ENTRENADOR'
            : newRole == AppUserRole.sinclave
                ? 'SIN CLAVE'
                : 'USUARIO';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.modalSurfaceFor(context),
        title: Text(
          'Confirmar cambio de rol',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        content: Text(
          '¿Seguro que quieres cambiar el rol de "${users[index].name}" a $action?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Cambiar',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    UserStore.instance.updateUserRole(index, newRole);
  }

  void _assignRoutineToUser(
    int index,
    String routineName,
    List<DateTime> dates,
  ) {
    UserStore.instance.assignRoutineOnDates(index, routineName, dates);
  }

  Future<void> _deleteUserFirestoreData(
    String userId,
    String adminId,
  ) async {
    final db = FirebaseFirestore.instance;
    try {
      // 2. Borrar datos ricos del usuario (entrenos, evolución, etc.)
      await db.collection('user_rich_data').doc(userId).delete();
    } catch (_) {}
    try {
      // 3. Borrar el chat entre admin y este usuario
      final ids = [adminId, userId]..sort();
      final convId = '${ids[0]}__${ids[1]}';
      final chatRef = db.collection('chats').doc(convId);
      // Borrar todos los mensajes primero (subcolección)
      final msgs = await chatRef.collection('messages').get();
      final batch = db.batch();
      for (final doc in msgs.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(chatRef);
      await batch.commit();
    } catch (_) {}
    try {
      // 4. Forzar guardado inmediato de app_state/users sin este usuario
      await CloudSyncService.instance.saveNow();
    } catch (_) {}
  }

  Future<void> _deleteUser(int index) async {
    final user = UserStore.instance.users[index];
    if (UserStore.instance.isCurrentUser(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes eliminar al admin principal.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final name = user.name;
    final userId = user.id;
    final adminId = UserStore.instance.currentUser.id;

    UserStore.instance.deleteUser(index);

    // Esperar a que Firestore quede actualizado antes de continuar
    await _deleteUserFirestoreData(userId, adminId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Usuario "$name" eliminado'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editExercise(int index) async {
    final oldExercise = ExerciseStore.instance.exercises[index];
    final result = await _openExerciseForm(existing: oldExercise);
    if (result != null && mounted) {
      ExerciseStore.instance.update(index, result);
      if (result.name != oldExercise.name) {
        UserStore.instance.renameExerciseInAllLogs(oldExercise.name, result.name);
        WorkoutRoutineStore.instance.renameExerciseInAllRoutines(oldExercise.name, result.name);
        unawaited(CloudSyncService.instance.saveNow());
      }
    }
  }

  void _deleteExercise(int index) => ExerciseStore.instance.remove(index);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel de Admin',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          _AdminTabs(
            tabs: _tabs,
            selectedIndex: _selectedTab,
            onSelected: _setSelectedTab,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_selectedTab),
                child: _buildContent(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_selectedTab) {
      case 0:
        return _buildUsersSection(context);
      case 1:
        return _RoutinesCatalogAdmin(
          routines: _routines,
          onAdd: _createRoutineFromTab,
          onEdit: _editRoutine,
          onDelete: _deleteRoutine,
        );
      case 2:
        return ListenableBuilder(
          listenable: ExerciseStore.instance,
          builder: (context, _) => _ExerciseCatalogAdmin(
            exercises: ExerciseStore.instance.exercises,
            onEdit: _editExercise,
            onDelete: _deleteExercise,
            onAdd: _addExerciseFromTab,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUsersSection(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final me = UserStore.instance.currentUser;
        final myId = me.id;
        final isAdmin = me.role == AppUserRole.admin;
        final allUsers = UserStore.instance.users;

        final roleFiltered = allUsers.where((u) {
          if (u.id == myId) return true;
          if (isAdmin) {
            // Admin: ver entrenadores, usuarios 'sinclave', y usuarios asignados al admin
            return u.role == AppUserRole.trainer ||
                u.role == AppUserRole.sinclave ||
                (u.role == AppUserRole.user && u.trainerId == myId);
          } else {
            return u.role == AppUserRole.user && u.trainerId == myId;
          }
        }).toList();

        final filteredEntries = roleFiltered.asMap().entries.where((entry) {
          if (_searchQuery.trim().isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return entry.value.name.toLowerCase().contains(q) ||
              entry.value.email.toLowerCase().contains(q);
        }).toList();
        final mine = filteredEntries.where((entry) => entry.value.id == myId);
        final others = filteredEntries.where((entry) => entry.value.id != myId);
        final orderedEntries = [...mine, ...others];

        return SizedBox.expand(
        child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.modalSurfaceFor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.modalBorderFor(context)),
                  boxShadow: AppTheme.modalShadowFor(context),
                ),
                child: ListView(
                  primary: false,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Buscar usuario por nombre o email...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF8C8C8C),
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.62),
                          ),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                                ),
                          filled: true,
                          fillColor: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).cardColor
                              : const Color(0xFFE8E8EC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppTheme.surfaceBorderFor(context),
                              width: Theme.of(context).brightness == Brightness.light
                                  ? 1.25
                                  : 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppTheme.surfaceBorderFor(context),
                              width: Theme.of(context).brightness == Brightness.light
                                  ? 1.25
                                  : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (orderedEntries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).cardColor
                                : const Color(0xFFE8E8EC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.surfaceBorderFor(context),
                              width: Theme.of(context).brightness == Brightness.light
                                  ? 1.25
                                  : 1,
                            ),
                            boxShadow: AppTheme.surfaceShadowFor(
                              context,
                              alpha: 0.08,
                              blurRadius: 12,
                              offsetY: 3,
                              addTopHighlight: true,
                            ),
                          ),
                          child: Text(
                            'No hay usuarios que coincidan con la busqueda.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      )
                    else
                      ...List.generate(orderedEntries.length, (visibleIndex) {
                        final entry = orderedEntries[visibleIndex];
                        final originalIndex = entry.key;
                        final u = entry.value;
                        final isCurrentUser = u.id == myId;

                        return Column(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openUserDetails(context, originalIndex),
                                splashColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                focusColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      _UserAvatar(
                                        name: u.name,
                                        photoBytes: u.photoBytes,
                                        photoUrl: u.photoUrl,
                                        size: 38,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              u.name,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (isCurrentUser) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.16),
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  'Tu',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 2),
                                            Text(
                                              u.email,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.62),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      PopupMenuButton<_UserQuickAction>(
                                        tooltip: 'Acciones',
                                        color: Theme.of(context).colorScheme.surface,
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                        onSelected: (action) => _onUserQuickAction(
                                          context,
                                          originalIndex,
                                          action,
                                        ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: _UserQuickAction.viewProfile,
                                            child: Text(
                                              'Ver perfil',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _UserQuickAction.assignRoutine,
                                            child: Text(
                                              'Asignar rutina',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _UserQuickAction.viewHistory,
                                            child: Text(
                                              'Ver historial',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _UserQuickAction.viewProgress,
                                            child: Text(
                                              'Ver progreso',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _UserQuickAction.viewEvolution,
                                            child: Text(
                                              'Ver evolucion',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: _UserQuickAction.viewTracking,
                                            child: Text(
                                              'Ver seguimiento',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (visibleIndex != orderedEntries.length - 1)
                              Container(
                                height: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.18),
                              ),
                          ],
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
          if (UserStore.instance.currentUser.role == AppUserRole.admin ||
              UserStore.instance.currentUser.role == AppUserRole.trainer)
            Positioned(
              right: 18,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 84,
              child: GestureDetector(
                onTap: _openAdminQuickMenuSheet,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      );
      },
    );
  }

  String _randomCode(String prefix, int len) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random();
    return '$prefix-${List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join()}';
  }

  Future<String> _getOrCreateAdminUserCode() async {
    final current = UserStore.instance.currentUser;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? current.id;
    if (uid.isEmpty) return '';

    final users = FirebaseFirestore.instance.collection('users');
    final keys = FirebaseFirestore.instance.collection('access_keys');

    var code = (current.trainerCode ?? '').trim();
    if (code.isEmpty) {
      final doc = await users.doc(uid).get();
      code = ((doc.data()?['codigoEntrenador'] as String?) ?? '').trim();
    }

    if (code.isNotEmpty) {
      await keys.doc(code).set({
        'tipo': 'user',
        'entrenadorId': uid,
        'usado': false,
      }, SetOptions(merge: true));
      return code;
    }

    for (var i = 0; i < 10; i++) {
      final next = _randomCode('ENTR', 6);
      final snap = await keys.doc(next).get();
      if (snap.exists) continue;
      final batch = FirebaseFirestore.instance.batch();
      batch.set(keys.doc(next), {
        'tipo': 'user',
        'entrenadorId': uid,
        'usado': false,
      });
      batch.set(users.doc(uid), {'codigoEntrenador': next}, SetOptions(merge: true));
      await batch.commit();
      return next;
    }
    return '';
  }

  Future<String> _getOrCreateTrainerCode() async {
    if (UserStore.instance.currentUser.role != AppUserRole.admin) return '';
    final keys = FirebaseFirestore.instance.collection('access_keys');

    // Prioriza siempre codigos reales existentes de tipo trainer_upgrade.
    try {
      final upgradeSnap = await keys
          .where('tipo', isEqualTo: 'trainer_upgrade')
          .limit(50)
          .get();
      final available = upgradeSnap.docs
          .where((doc) => (doc.data()['usado'] as bool?) != true)
          .map((doc) => doc.id)
          .where((id) => id.trim().isNotEmpty)
          .toList()
        ..sort();
      if (available.isNotEmpty) {
        return available.first;
      }
    } catch (_) {}

    try {
      final legacyTrainerSnap = await keys
          .where('tipo', isEqualTo: 'trainer')
          .limit(50)
          .get();
      final available = legacyTrainerSnap.docs
          .where((doc) => (doc.data()['usado'] as bool?) != true)
          .map((doc) => doc.id)
          .where((id) => id.trim().isNotEmpty)
          .toList()
        ..sort();
      if (available.isNotEmpty) {
        return available.first;
      }
    } catch (_) {}

    for (var i = 0; i < 8; i++) {
      final next = _randomCode('TRUP', 8);
      final snap = await keys.doc(next).get();
      if (snap.exists) continue;
      try {
        await keys.doc(next).set({
          'tipo': 'trainer_upgrade',
          'usado': false,
        });
        return next;
      } catch (_) {
        try {
          await keys.doc(next).set({
            'tipo': 'trainer',
            'usado': false,
          });
          return next;
        } catch (_) {}
      }
    }
    return '';
  }

  Future<void> _loadAdminCodes() async {
    if (_loadingCodes) return;
    setState(() => _loadingCodes = true);
    var nextUserCode = _adminUserCode;
    var nextTrainerCode = '';

    try {
      nextUserCode = await _getOrCreateAdminUserCode();
    } catch (_) {
      // Mantener valor previo si falla.
    }

    try {
      nextTrainerCode = await _getOrCreateTrainerCode();
    } catch (_) {
      // Mantener valor previo si falla.
    }

    if (!mounted) return;
    setState(() {
      _adminUserCode = nextUserCode;
      _trainerUpgradeCode = nextTrainerCode;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty && _adminUserCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo cargar tu codigo de usuarios. Revisa permisos de Firestore en access_keys/users.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // noop
    }

    if (mounted) setState(() => _loadingCodes = false);
  }

  Future<void> _openTrainerQuestionnaireEditor() async {
    final questions = UserStore.instance.questionnaireTemplateQuestions();
    final result = await showQuestionnaireEditorDialog(
      context,
      title: 'Editar cuestionario',
      initialQuestions: questions,
      initialAnswers: const <String, String>{},
      allowQuestionEditing: true,
      dismissible: true,
    );
    if (result == null) return;
    UserStore.instance.saveQuestionnaireTemplateForAllUsers(
      questions: result.questions,
    );
  }

  Future<void> _copyCode(String label, String code) async {
    final normalized = code.trim();
    if (normalized.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: normalized));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  Widget _fabMenuRow({
    required BuildContext context,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    IconData trailingIcon = Icons.copy_rounded,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.68),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            Icon(trailingIcon, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdminQuickMenuSheet() async {
    await _loadAdminCodes();
    if (!mounted) return;
    final role = UserStore.instance.currentUser.role;
    final isAdmin = role == AppUserRole.admin;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.surfaceBorderFor(sheetContext)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (isAdmin) ...[
                _fabMenuRow(
                  context: sheetContext,
                  title: 'Codigo de entrenador',
                  subtitle: _trainerUpgradeCode.isEmpty ? 'No disponible' : _trainerUpgradeCode,
                  onTap: () => _copyCode('Codigo de entrenador', _trainerUpgradeCode),
                ),
                Container(height: 1, color: AppTheme.surfaceBorderFor(sheetContext)),
              ],
              _fabMenuRow(
                context: sheetContext,
                title: 'Codigo de usuarios',
                subtitle: _adminUserCode.isEmpty ? 'No disponible' : _adminUserCode,
                onTap: () => _copyCode('Codigo de usuarios', _adminUserCode),
              ),
              Container(height: 1, color: AppTheme.surfaceBorderFor(sheetContext)),
              _fabMenuRow(
                context: sheetContext,
                title: 'Editar cuestionario',
                trailingIcon: Icons.edit_note_rounded,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _openTrainerQuestionnaireEditor();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAssignRoutineSheet(BuildContext context, int index) async {
    if (_routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea una rutina primero para poder asignarla.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<_RoutineScheduleSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoutineScheduleSheet(
        routines: _routines,
        onCreateRoutine: _createRoutineFromUserModal,
      ),
    );

    if (result == null) return;
    _assignRoutineToUser(index, result.routineName, result.dates);
  }

  Future<void> _onUserQuickAction(
    BuildContext context,
    int index,
    _UserQuickAction action,
  ) async {
    switch (action) {
      case _UserQuickAction.assignRoutine:
        await _openAssignRoutineSheet(context, index);
      case _UserQuickAction.viewProfile:
        await _openUserDetails(context, index);
      case _UserQuickAction.viewHistory:
        await _openUserWorkoutHistorySheet(context, index);
      case _UserQuickAction.viewProgress:
        await _openUserProgressSheet(context, index);
      case _UserQuickAction.viewEvolution:
        await _openUserEvolutionSheet(context, index);
      case _UserQuickAction.viewTracking:
        await _openUserTrackingSheet(context, index);
      case _UserQuickAction.changeRole:
        await _openRoleChangeSheet(context, index);
    }
  }

  Future<void> _openRoleChangeSheet(BuildContext context, int index) async {
    final user = UserStore.instance.users[index];
    final selected = await showModalBottomSheet<AppUserRole>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: AppTheme.surfaceBorderFor(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.26),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                title: const Text('Usuario'),
                trailing: user.role == AppUserRole.user
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, AppUserRole.user),
              ),
              ListTile(
                title: const Text('Sin clave'),
                trailing: user.role == AppUserRole.sinclave
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, AppUserRole.sinclave),
              ),
              ListTile(
                title: const Text('Entrenador'),
                trailing: user.role == AppUserRole.trainer
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, AppUserRole.trainer),
              ),
              ListTile(
                title: const Text('Admin'),
                trailing: user.role == AppUserRole.admin
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, AppUserRole.admin),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (selected == null || selected == user.role) return;
    await _changeUserRole(index, selected);
  }

  Future<void> _openUserWorkoutHistorySheet(
    BuildContext context,
    int index,
  ) async {
    final user = UserStore.instance.users[index];
    final assignments = [...user.scheduledRoutines]
      ..sort(
        (left, right) => right.normalizedDate.compareTo(left.normalizedDate),
      );
    final history = [...user.completedWorkouts]
      ..sort(
        (left, right) => right.normalizedDate.compareTo(left.normalizedDate),
      );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: AppTheme.surfaceBorderFor(context)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Historial de ${user.name}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${history.length} entrenos completados · ${assignments.length} asignados',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              if (history.isEmpty && assignments.isEmpty)
                Text(
                  'Este usuario todavia no tiene rutinas en su historial.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                )
              else ...[
                ...history.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                    leading: const Icon(Icons.fitness_center_rounded),
                    title: Text(item.routineName),
                    subtitle: Text(_formatDateLong(item.date)),
                    trailing: Text(_formatSecondsAsClock(item.totalSeconds)),
                    onTap: () => _openWorkoutDetailSheet(
                      context,
                      routineName: item.routineName,
                      completion: item,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWorkoutDetailSheet(
    BuildContext context, {
    required String routineName,
    WorkoutCompletion? completion,
  }) {
    final routine = WorkoutRoutineStore.instance.byName(routineName);
    final exercises = routine?.exercises ?? const <WorkoutRoutineExercise>[];
    final fallbackRoutine = routine == null
        ? _routines.cast<_RoutineData?>().firstWhere(
            (item) => item?.name == routineName,
            orElse: () => null,
          )
        : null;
    final isCompleted = completion != null;
    final detailTiles = <Widget>[];

    if (exercises.isNotEmpty) {
      detailTiles.addAll(
        exercises.map(
          (exercise) => Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
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
                  exercise.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  exercise.mode == WorkoutExerciseMode.timed
                      ? 'Tiempo: ${exercise.durationSeconds}s · Descanso: ${exercise.restSeconds}s'
                      : 'Series: ${exercise.sets ?? 0} · Reps: ${exercise.reps ?? 0} · Descanso: ${exercise.restSeconds}s',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (fallbackRoutine != null &&
        fallbackRoutine.exercises.isNotEmpty) {
      detailTiles.addAll(
        fallbackRoutine.exercises.map(
          (spec) => Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
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
                  spec.exercise.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  spec.type == _RoutineSpecType.time
                      ? 'Tiempo: ${spec.workSeconds ?? 0}s · Descanso: ${spec.restSeconds ?? 0}s'
                      : 'Series: ${spec.sets ?? 0} · Reps: ${spec.reps ?? 0} · Descanso: ${spec.restSeconds}s',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            Text(
              routineName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              isCompleted
                  ? 'Realizado el ${_formatDateLong(completion.date)}'
                  : 'Rutina pendiente',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBorderFor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isCompleted
                        ? 'Duracion ${_formatSecondsAsClock(completion.totalSeconds)}'
                        : 'Pendiente de completar',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBorderFor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isCompleted
                        ? 'Puntuacion ${completion.rating}/5'
                        : 'Sin puntuacion',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBorderFor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${exercises.length} ejercicios',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            if (detailTiles.isEmpty)
              Text(
                'No se encontraron detalles de la rutina en el catalogo actual.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              )
            else
              ...detailTiles,
          ],
        ),
      ),
    );
  }

  Future<void> _openUserProgressSheet(BuildContext context, int index) {
    String searchQuery = '';

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.86,
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: UserStore.instance,
              builder: (context, _) {
                if (index >= UserStore.instance.users.length) {
                  return const SizedBox.shrink();
                }

                final user = UserStore.instance.users[index];
                final completedCount = user.completedWorkouts.length;
                final assignedCount = user.scheduledRoutines.length;
                final trackedCount = user.trackingHistory.length;
                final uniqueRoutines = user.completedWorkouts
                    .map((item) => item.routineName)
                    .toSet()
                    .length;
                final latestWorkoutDate = user.completedWorkouts.isEmpty
                    ? null
                    : user.completedWorkouts
                          .map((item) => item.normalizedDate)
                          .reduce(
                            (left, right) => left.isAfter(right) ? left : right,
                          );

                final logs = UserStore.instance.exerciseWeightLogsForUser(
                  index,
                );
                final grouped = <String, List<ExerciseWeightLogEntry>>{};
                for (final item in logs) {
                  grouped.putIfAbsent(item.exerciseName, () => []).add(item);
                }

                final normalizedSearch = searchQuery.trim().toLowerCase();
                final exerciseNames =
                    grouped.keys
                        .where(
                          (name) =>
                              normalizedSearch.isEmpty ||
                              name.toLowerCase().contains(normalizedSearch),
                        )
                        .toList()
                      ..sort((a, b) {
                        final ad = grouped[a]!.first.date;
                        final bd = grouped[b]!.first.date;
                        return bd.compareTo(ad);
                      });

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  children: [
                    Text(
                      'Progreso de ${user.name}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _UserDataTile(
                          label: 'Entrenos',
                          value: '$completedCount',
                          icon: Icons.fitness_center_rounded,
                        ),
                        _UserDataTile(
                          label: 'Rutinas hechas',
                          value: '$uniqueRoutines',
                          icon: Icons.checklist_rounded,
                        ),
                        _UserDataTile(
                          label: 'Asignaciones',
                          value: '$assignedCount',
                          icon: Icons.event_note_rounded,
                        ),
                        _UserDataTile(
                          label: 'Registros',
                          value: '$trackedCount',
                          icon: Icons.monitor_heart_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (latestWorkoutDate != null)
                      Text(
                        'Ultimo entreno completado: ${_formatDateLong(latestWorkoutDate)}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                          fontSize: 12,
                        ),
                      )
                    else
                      Text(
                        'Aun no hay entrenos completados para mostrar progreso.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Pesos',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openAddWeightForUserSheet(
                          context,
                          userIndex: index,
                          onSaved: () => setSheetState(() {}),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text(
                          'Añadir peso al historial',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.surfaceBorderFor(context),
                          width:
                              Theme.of(context).brightness == Brightness.light
                              ? 1.25
                              : 1,
                        ),
                      ),
                      child: TextField(
                        onChanged: (value) =>
                            setSheetState(() => searchQuery = value),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Buscar ejercicio...',
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                          icon: Icon(
                            Icons.search_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (grouped.isEmpty)
                      Text(
                        'Este usuario aun no tiene pesos registrados en ejercicios.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                        ),
                      )
                    else if (exerciseNames.isEmpty)
                      Text(
                        'No se encontraron ejercicios con ese nombre.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                        ),
                      )
                    else
                      ...exerciseNames.map((exerciseName) {
                        final exerciseLogs = grouped[exerciseName]!;
                        final latest = exerciseLogs.first;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openExerciseWeightDetailSheet(
                                context,
                                userIndex: index,
                                exerciseName: exerciseName,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.surfaceBorderFor(context),
                                    width:
                                        Theme.of(context).brightness ==
                                            Brightness.light
                                        ? 1.25
                                        : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            exerciseName,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${latest.weightKg.toStringAsFixed(latest.weightKg % 1 == 0 ? 0 : 1)} kg',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Último registro: ${_formatDateLong(latest.date)} · Total: ${exerciseLogs.length}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.62),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openExerciseWeightDetailSheet(
    BuildContext context, {
    required int userIndex,
    required String exerciseName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminExerciseWeightDetailSheet(
        userIndex: userIndex,
        exerciseName: exerciseName,
        formatDate: _formatDateLong,
      ),
    );
  }

  Future<void> _openAddWeightForUserSheet(
    BuildContext context, {
    required int userIndex,
    VoidCallback? onSaved,
    String? initialExerciseName,
  }) {
    final exerciseCtrl = TextEditingController(text: initialExerciseName ?? '');
    final weightCtrl = TextEditingController();

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Añadir peso al historial',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: exerciseCtrl,
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Ejercicio',
                      labelStyle: TextStyle(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Peso (kg)',
                      labelStyle: TextStyle(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final exercise = exerciseCtrl.text.trim();
                        final parsed = double.tryParse(
                          weightCtrl.text.trim().replaceAll(',', '.'),
                        );
                        if (exercise.isEmpty || parsed == null || parsed <= 0) {
                          return;
                        }
                        UserStore.instance.addExerciseWeightForUser(
                          userIndex,
                          exerciseName: exercise,
                          weightKg: parsed,
                          date: DateTime.now(),
                        );
                        Navigator.pop(sheetContext);
                        onSaved?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          sheetContext,
                        ).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Guardar peso',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _openUserWeightHistorySheet(BuildContext context, int index) {
    String searchQuery = '';

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: ListenableBuilder(
            listenable: UserStore.instance,
            builder: (context, _) {
              if (index >= UserStore.instance.users.length) {
                return const SizedBox.shrink();
              }

              final user = UserStore.instance.users[index];
              final logs = UserStore.instance.exerciseWeightLogsForUser(index);
              final grouped = <String, List<ExerciseWeightLogEntry>>{};
              for (final item in logs) {
                grouped.putIfAbsent(item.exerciseName, () => []).add(item);
              }
              final normalizedSearch = searchQuery.trim().toLowerCase();
              final names =
                  grouped.keys
                      .where(
                        (name) =>
                            normalizedSearch.isEmpty ||
                            name.toLowerCase().contains(normalizedSearch),
                      )
                      .toList()
                    ..sort((a, b) {
                      final ad = grouped[a]!.first.date;
                      final bd = grouped[b]!.first.date;
                      return bd.compareTo(ad);
                    });

              return ListView(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 24),
                children: [
                  Text(
                    'Pesos de ${user.name}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${logs.length} registros totales',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.surfaceBorderFor(context),
                        width: Theme.of(context).brightness == Brightness.light
                            ? 1.25
                            : 1,
                      ),
                    ),
                    child: TextField(
                      onChanged: (value) =>
                          setSheetState(() => searchQuery = value),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Buscar ejercicio...',
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                        ),
                        icon: Icon(
                          Icons.search_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 14),
                  if (grouped.isEmpty)
                    Text(
                      'Este usuario aun no tiene pesos registrados en ejercicios.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    )
                  else if (names.isEmpty)
                    Text(
                      'No se encontraron ejercicios con ese nombre.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    )
                  else
                    ...names.map((exerciseName) {
                      final exerciseLogs = grouped[exerciseName]!;
                      final latest = exerciseLogs.first;
                      return Container(
                        margin: EdgeInsets.only(bottom: 10),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.surfaceBorderFor(context),
                            width:
                                Theme.of(context).brightness == Brightness.light
                                ? 1.25
                                : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    exerciseName,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${latest.weightKg.toStringAsFixed(latest.weightKg % 1 == 0 ? 0 : 1)} kg',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...exerciseLogs
                                .take(6)
                                .map(
                                  (item) => Padding(
                                    padding: EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          size: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _formatDateLong(item.date),
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.62),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${item.weightKg.toStringAsFixed(item.weightKg % 1 == 0 ? 0 : 1)} kg',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openUserEvolutionSheet(BuildContext context, int index) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.84,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          child: EvolutionTab(
            userIndex: index,
            adminMode: true,
            allowCreateTests: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openUserTrackingSheet(BuildContext context, int index) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.modalSurfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ListenableBuilder(
          listenable: UserStore.instance,
          builder: (context, _) {
            if (index >= UserStore.instance.users.length) {
              return const SizedBox.shrink();
            }

            final user = UserStore.instance.users[index];
            final history = UserStore.instance.trackingHistoryForUser(index);

            return ListView(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 24),
              children: [
                Text(
                  'Seguimiento de ${user.name}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${history.length} registros guardados',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 14),
                if (history.isEmpty)
                  Text(
                    'Este usuario aun no ha guardado registros de seguimiento.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  )
                else
                  ...history.map(
                    (item) => Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.surfaceBorderFor(context),
                          width:
                              Theme.of(context).brightness == Brightness.light
                              ? 1.25
                              : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDateLong(item.date),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.photoBytes != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                item.photoBytes!,
                                height: 110,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          ..._buildTrackingLine('Peso', item.weightKg, 'kg'),
                          ..._buildTrackingLine('Cintura', item.waistCm, 'cm'),
                          ..._buildTrackingLine('Cadera', item.hipsCm, 'cm'),
                          ..._buildTrackingLine('Brazos', item.armsCm, 'cm'),
                          ..._buildTrackingLine('Muslos', item.thighsCm, 'cm'),
                          ..._buildTrackingLine('Gemelos', item.calvesCm, 'cm'),
                          ..._buildTrackingLine(
                            'Antebrazo',
                            item.forearmCm,
                            'cm',
                          ),
                          ..._buildTrackingLine('Cuello', item.neckCm, 'cm'),
                          ..._buildTrackingLine('Pecho', item.chestCm, 'cm'),
                          if (item.notes.trim().isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Notas: ${item.notes.trim()}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildTrackingLine(String label, double? value, String unit) {
    if (value == null) return <Widget>[];
    return [
      Text(
        '$label: ${value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} $unit',
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.62),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    ];
  }

  Future<void> _openUserDetails(BuildContext context, int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => ListenableBuilder(
          listenable: UserStore.instance,
          builder: (context, _) {
            if (index >= UserStore.instance.users.length) {
              return const SizedBox.shrink();
            }

            final currentUser = UserStore.instance.users[index];
            final isCurrentUser = UserStore.instance.isCurrentUser(currentUser);
            return Container(
              margin: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.08,
              ),
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(context),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 6),
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors:
                              Theme.of(context).brightness == Brightness.dark
                              ? const [Color(0xFF2A1907), Color(0xFF151515)]
                              : [
                                  Theme.of(context).cardColor,
                                  Theme.of(context).colorScheme.surface,
                                ],
                        ),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF3A2A16)
                              : AppTheme.surfaceBorderFor(context),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _UserAvatar(
                              name: currentUser.name,
                              photoBytes: currentUser.photoBytes,
                              photoUrl: currentUser.photoUrl,
                              size: 58,
                              fontSize: 22,
                              elevated: true,
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentUser.name,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    currentUser.email,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.62),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _ProfileMetaChip(
                                        icon: Icons.workspace_premium_rounded,
                                        text:
                                            currentUser.role ==
                                                AppUserRole.admin
                                            ? 'Admin'
                                            : 'Usuario',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(
                                Icons.close_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      children: [
                        _ProfileInfoCard(
                          title: isCurrentUser
                              ? 'Tus datos sincronizados'
                              : 'Ficha del cliente',
                          icon: Icons.badge_outlined,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _UserDataTile(
                                  label: 'Edad',
                                  value: currentUser.age?.toString() ?? '-',
                                  icon: Icons.cake_outlined,
                                ),
                                _UserDataTile(
                                  label: 'Nivel',
                                  value: currentUser.level ?? 'Sin nivel',
                                  icon: Icons.flag_outlined,
                                ),
                                _UserDataTile(
                                  label: 'Peso',
                                  value: currentUser.weightKg == null
                                      ? '-'
                                      : '${currentUser.weightKg} kg',
                                  icon: Icons.monitor_weight_outlined,
                                ),
                                _UserDataTile(
                                  label: 'Altura',
                                  value: currentUser.heightCm == null
                                      ? '-'
                                      : '${currentUser.heightCm} cm',
                                  icon: Icons.height_rounded,
                                ),
                                _UserDataTile(
                                  label: 'Objetivos',
                                  value: currentUser.objectives.isEmpty
                                      ? '-'
                                      : currentUser.objectives.join(', '),
                                  icon: Icons.flag_outlined,
                                  isWide: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _QuestionnaireSummaryCard(
                          questions: currentUser.questionnaireQuestions,
                          answers: {
                            for (final item
                                in currentUser.questionnaireResponses)
                              item.questionId: item.answer,
                          },
                          completedAt: currentUser.questionnaireCompletedAt,
                        ),
                        SizedBox(height: 14),
                        if (isCurrentUser)
                          Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Color(0xFF2E2E2E)),
                            ),
                            child: Text(
                              'Este usuario se sincroniza directamente con los datos guardados en Perfil y no puede eliminarse.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: AppTheme.modalSurfaceFor(
                                      context,
                                    ),
                                    title: Text(
                                      'Eliminar usuario',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    content: Text(
                                      '¿Seguro que quieres eliminar este usuario?',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.62),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(
                                          'Cancelar',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.62),
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Eliminar',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                await _deleteUser(index);
                                if (context.mounted) Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8E2424),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Eliminar usuario'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoutineScheduleSelection {
  const _RoutineScheduleSelection({
    required this.routineName,
    required this.dates,
  });

  final String routineName;
  final List<DateTime> dates;
}

class _RoutineScheduleSheet extends StatefulWidget {
  const _RoutineScheduleSheet({
    required this.routines,
    required this.onCreateRoutine,
  });

  final List<_RoutineData> routines;
  final Future<_RoutineData?> Function() onCreateRoutine;

  @override
  State<_RoutineScheduleSheet> createState() => _RoutineScheduleSheetState();
}

class _RoutineScheduleSheetState extends State<_RoutineScheduleSheet> {
  late TextEditingController _routineSearchCtrl;
  String _routineQuery = '';
  String? _selectedRoutineName;
  final Set<DateTime> _selectedDates = <DateTime>{};
  int _monthAheadOffset = 0;

  @override
  void initState() {
    super.initState();
    _routineSearchCtrl = TextEditingController();
    _selectedRoutineName = widget.routines.isEmpty
        ? null
        : widget.routines.first.name;
  }

  @override
  void dispose() {
    _routineSearchCtrl.dispose();
    super.dispose();
  }

  void _toggleDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() {
      if (_selectedDates.contains(normalized)) {
        _selectedDates.remove(normalized);
      } else {
        _selectedDates.add(normalized);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final now = DateTime.now();
    final visibleMonth = DateTime(now.year, now.month + _monthAheadOffset, 1);
    final filteredRoutines = widget.routines
        .where(
          (routine) => routine.name.toLowerCase().contains(
            _routineQuery.toLowerCase().trim(),
          ),
        )
        .toList();

    final selectedRoutine = _selectedRoutineName;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: AppTheme.surfaceBorderFor(context),
            width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            width: 52,
            height: 5,
            decoration: BoxDecoration(
              color: AppTheme.surfaceBorderFor(context),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Asignar rutina',
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.14),
                        theme.cardColor,
                      ],
                    ),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Rutina a asignar',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final created = await widget.onCreateRoutine();
                              if (!mounted || created == null) return;
                              setState(() {
                                _selectedRoutineName = created.name;
                                _routineQuery = '';
                                _routineSearchCtrl.clear();
                              });
                            },
                            icon: Icon(
                              Icons.add_circle_outline_rounded,
                              size: 14,
                            ),
                            label: Text('Crear rutina'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _routineSearchCtrl,
                        style: TextStyle(color: onSurface),
                        onChanged: (value) =>
                            setState(() => _routineQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Buscar rutina...',
                          hintStyle: TextStyle(color: muted, fontSize: 13),
                          prefixIcon: Icon(Icons.search_rounded, color: muted),
                          suffixIcon: _routineQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _routineSearchCtrl.clear();
                                    setState(() => _routineQuery = '');
                                  },
                                  icon: Icon(Icons.close_rounded, color: muted),
                                ),
                          filled: true,
                          fillColor: theme.cardColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.surfaceBorderFor(context),
                              width:
                                  Theme.of(context).brightness ==
                                      Brightness.light
                                  ? 1.25
                                  : 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.surfaceBorderFor(context),
                              width:
                                  Theme.of(context).brightness ==
                                      Brightness.light
                                  ? 1.25
                                  : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        constraints: BoxConstraints(maxHeight: 164),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.surfaceBorderFor(context),
                            width:
                                Theme.of(context).brightness == Brightness.light
                                ? 1.25
                                : 1,
                          ),
                        ),
                        child: filteredRoutines.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Text(
                                    'No se encontraron rutinas.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                itemCount: filteredRoutines.length,
                                separatorBuilder: (context, index) => Divider(
                                  color: AppTheme.surfaceBorderFor(context),
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final routine = filteredRoutines[index];
                                  final isSelected =
                                      selectedRoutine == routine.name;
                                  return InkWell(
                                    onTap: () => setState(
                                      () => _selectedRoutineName = routine.name,
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color.fromRGBO(
                                                255,
                                                152,
                                                0,
                                                0.18,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Text(
                                        routine.name,
                                        style: TextStyle(
                                          color: isSelected ? onSurface : muted,
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Selecciona uno o varios días del mes actual o del próximo mes.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SelectableMonthlyCalendar(
                  monthDate: visibleMonth,
                  canGoPrevious: _monthAheadOffset > 0,
                  canGoNext: _monthAheadOffset < 1,
                  onPreviousMonth: () => setState(() => _monthAheadOffset -= 1),
                  onNextMonth: () => setState(() => _monthAheadOffset += 1),
                  selectedDates: _selectedDates,
                  onToggleDate: _toggleDate,
                ),
                const SizedBox(height: 16),
                if (_selectedDates.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ([..._selectedDates]..sort())
                        .map(
                          (date) => _ProfileMetaChip(
                            icon: Icons.event_rounded,
                            text: _formatDateLong(date),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedRoutine == null || _selectedDates.isEmpty
                        ? null
                        : () {
                            Navigator.pop(
                              context,
                              _RoutineScheduleSelection(
                                routineName: selectedRoutine,
                                dates: _selectedDates.toList()..sort(),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      selectedRoutine == null
                          ? 'Selecciona una rutina'
                          : _selectedDates.isEmpty
                          ? 'Selecciona al menos un día'
                          : 'Asignar a ${_selectedDates.length} día${_selectedDates.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableMonthlyCalendar extends StatelessWidget {
  const _SelectableMonthlyCalendar({
    required this.monthDate,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.selectedDates,
    required this.onToggleDate,
  });

  final DateTime monthDate;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final Set<DateTime> selectedDates;
  final ValueChanged<DateTime> onToggleDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.62);
    final firstDay = DateTime(monthDate.year, monthDate.month, 1);
    final lastDay = DateTime(monthDate.year, monthDate.month + 1, 0);
    final offset = (firstDay.weekday + 6) % 7;
    final totalDays = lastDay.day;
    final monthTitle =
        '${_capitalize(_kMonthNames[monthDate.month - 1])} ${monthDate.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: canGoPrevious ? onPreviousMonth : null,
                icon: const Icon(Icons.chevron_left_rounded),
                color: muted,
              ),
              Expanded(
                child: Text(
                  monthTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: canGoNext ? onNextMonth : null,
                icon: const Icon(Icons.chevron_right_rounded),
                color: muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _kWeekLabels.length + offset + totalDays,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.96,
            ),
            itemBuilder: (context, index) {
              if (index < _kWeekLabels.length) {
                return Center(
                  child: Text(
                    _kWeekLabels[index],
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8F8F8F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }

              final calendarIndex = index - _kWeekLabels.length;
              if (calendarIndex < offset) {
                return const SizedBox.shrink();
              }

              final day = calendarIndex - offset + 1;
              final current = DateTime(monthDate.year, monthDate.month, day);
              final isToday = _isSameDate(current, DateTime.now());
              final isSelected = selectedDates.any(
                (date) => _isSameDate(date, current),
              );

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onToggleDate(current),
                  borderRadius: BorderRadius.circular(9),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Color.fromRGBO(255, 152, 0, 0.22)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : isToday
                            ? theme.colorScheme.primary.withValues(alpha: 0.75)
                            : AppTheme.surfaceBorderFor(context),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: 4,
                            top: 2,
                            child: Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _CompletedWorkoutCalendar extends StatelessWidget {
  const _CompletedWorkoutCalendar({
    required this.monthDate,
    required this.workouts,
    required this.selectedDay,
    required this.onTapDay,
  });

  final DateTime monthDate;
  final List<WorkoutCompletion> workouts;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(monthDate.year, monthDate.month, 1);
    final lastDay = DateTime(monthDate.year, monthDate.month + 1, 0);
    final offset = (firstDay.weekday + 6) % 7;
    final totalDays = lastDay.day;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _kWeekLabels.length + offset + totalDays,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.96,
        ),
        itemBuilder: (context, index) {
          if (index < _kWeekLabels.length) {
            return Center(
              child: Text(
                _kWeekLabels[index],
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8F8F8F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final calendarIndex = index - _kWeekLabels.length;
          if (calendarIndex < offset) {
            return const SizedBox.shrink();
          }

          final day = calendarIndex - offset + 1;
          final current = DateTime(monthDate.year, monthDate.month, day);
          final isToday = _isSameDate(current, DateTime.now());
          final hasWorkout = workouts.any((w) => _isSameDate(w.date, current));
          final isSelected =
              selectedDay != null && _isSameDate(selectedDay!, current);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTapDay(current),
              borderRadius: BorderRadius.circular(9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Color.fromRGBO(255, 152, 0, 0.20)
                      : hasWorkout
                      ? Color.fromRGBO(34, 197, 94, 0.18)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : hasWorkout
                        ? const Color(0xFF22C55E)
                        : isToday
                        ? const Color(0xFFE67E22)
                        : const Color(0xFF2A2A2A),
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? Color(0xFFFFE8C5)
                              : hasWorkout
                              ? Color(0xFFD7FFE7)
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected || hasWorkout
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (hasWorkout)
                      const Positioned(
                        right: 4,
                        top: 2,
                        child: Icon(
                          Icons.circle,
                          size: 7,
                          color: Color(0xFF86EFAC),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFF29292B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _QuestionnaireSummaryCard extends StatelessWidget {
  const _QuestionnaireSummaryCard({
    required this.questions,
    required this.answers,
    required this.completedAt,
  });

  final List<QuestionnaireQuestion> questions;
  final Map<String, String> answers;
  final DateTime? completedAt;

  @override
  Widget build(BuildContext context) {
    final answeredCount = answers.values
        .where((v) => v.trim().isNotEmpty)
        .length;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.quiz_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cuestionario',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            completedAt == null
                ? 'Pendiente de completar'
                : 'Respondido el ${_formatDateLong(completedAt!)}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 12,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '$answeredCount/${questions.length} respuestas guardadas',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ...questions.asMap().entries.map((entry) {
            final i = entry.key;
            final q = entry.value;
            final answer = (answers[q.id] ?? '').trim();
            return Container(
              width: double.infinity,
              margin: EdgeInsets.only(
                bottom: i == questions.length - 1 ? 0 : 8,
              ),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
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
                    'Pregunta ${i + 1}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    q.text,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(0xFF2E2E31)),
                    ),
                    child: Text(
                      answer.isEmpty ? 'Sin respuesta' : answer,
                      style: TextStyle(
                        color: answer.isEmpty
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.62)
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ProfileMetaChip extends StatelessWidget {
  const _ProfileMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Color(0xFF2F2F31)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.name,
    required this.photoBytes,
    required this.size,
    this.photoUrl = '',
    this.fontSize = 16,
    this.elevated = false,
  });

  final String name;
  final Uint8List? photoBytes;
  final String photoUrl;
  final double size;
  final double fontSize;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary,
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color.fromRGBO(255, 152, 0, 0.32),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: photoBytes != null
          ? Image.memory(
              photoBytes!,
              fit: BoxFit.cover,
              width: size,
              height: size,
            )
          : photoUrl.isNotEmpty
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, error, stackTrace) => Text(
                _initialsFromName(name),
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize,
                ),
              ),
            )
          : Text(
              _initialsFromName(name),
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
    );
  }
}

class _AdminExerciseWeightDetailSheet extends StatefulWidget {
  const _AdminExerciseWeightDetailSheet({
    required this.userIndex,
    required this.exerciseName,
    required this.formatDate,
  });

  final int userIndex;
  final String exerciseName;
  final String Function(DateTime date) formatDate;

  @override
  State<_AdminExerciseWeightDetailSheet> createState() =>
      _AdminExerciseWeightDetailSheetState();
}

class _AdminExerciseWeightDetailSheetState
    extends State<_AdminExerciseWeightDetailSheet> {
  final TextEditingController _weightCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  List<ExerciseWeightLogEntry> _logsForUser() {
    final all = UserStore.instance.exerciseWeightLogsForUser(widget.userIndex);
    return all
        .where((item) => item.exerciseName == widget.exerciseName)
        .toList();
  }

  void _saveWeight() {
    final parsed = double.tryParse(
      _weightCtrl.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return;
    UserStore.instance.addExerciseWeightForUser(
      widget.userIndex,
      exerciseName: widget.exerciseName,
      weightKg: parsed,
      date: DateTime.now(),
    );
    setState(() {
      _weightCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final modalColor = AppTheme.modalSurfaceFor(context);
    final modalBorder = AppTheme.modalBorderFor(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10),
      decoration: BoxDecoration(
        color: modalColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: modalBorder),
        boxShadow: AppTheme.modalShadowFor(context),
      ),
      child: ListenableBuilder(
        listenable: UserStore.instance,
        builder: (context, _) {
          final logs = _logsForUser();
          final chartPoints = logs.reversed.take(8).toList();

          return Column(
            children: [
              const SizedBox(height: 6),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                        Text(
                          'Volver',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF40311C),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Icon(
                                  Icons.trending_up_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.exerciseName,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${logs.length} registros',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.62),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: SizedBox(
                              height: 190,
                              child: _AdminWeightLineChart(points: chartPoints),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Agregar mas pesos',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _weightCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Peso en kg',
                                          hintStyle: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.62),
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).dividerColor,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: _saveWeight,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Guardar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Historial',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (logs.isEmpty)
                            Text(
                              'Aun no hay registros para este ejercicio.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                              ),
                            )
                          else
                            ...logs.map((item) {
                              final formatted = item.weightKg % 1 == 0
                                  ? item.weightKg.toStringAsFixed(0)
                                  : item.weightKg.toStringAsFixed(1);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        widget.formatDate(item.date),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$formatted kg',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminWeightLineChart extends StatefulWidget {
  const _AdminWeightLineChart({required this.points});

  final List<ExerciseWeightLogEntry> points;

  @override
  State<_AdminWeightLineChart> createState() => _AdminWeightLineChartState();
}

class _AdminWeightLineChartState extends State<_AdminWeightLineChart> {
  int? _selectedIndex;

  static const double _leftPad = 34.0;
  static const double _rightPad = 10.0;
  static const double _topPad = 12.0;
  static const double _bottomPad = 28.0;

  List<Offset> _computeOffsets(Size size) {
    final chartRect = Rect.fromLTWH(
      _leftPad,
      _topPad,
      size.width - _leftPad - _rightPad,
      size.height - _topPad - _bottomPad,
    );
    final pts = widget.points;
    final minW = pts.map((p) => p.weightKg).reduce(math.min);
    final maxW = pts.map((p) => p.weightKg).reduce(math.max);
    final range = (maxW - minW).abs() < 0.0001 ? 1.0 : (maxW - minW);
    return List.generate(pts.length, (i) {
      final dx = pts.length == 1
          ? chartRect.center.dx
          : chartRect.left + (chartRect.width * i / (pts.length - 1));
      final dy =
          chartRect.bottom -
          ((pts[i].weightKg - minW) / range) * chartRect.height;
      return Offset(dx, dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return Center(
        child: Text(
          'Sin datos',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapDown: (details) {
            final offsets = _computeOffsets(size);
            int? nearest;
            double minDist = 24.0;
            for (var i = 0; i < offsets.length; i++) {
              final d = (offsets[i] - details.localPosition).distance;
              if (d < minDist) {
                minDist = d;
                nearest = i;
              }
            }
            setState(() {
              _selectedIndex = nearest == _selectedIndex ? null : nearest;
            });
          },
          child: CustomPaint(
            painter: _AdminWeightLineChartPainter(
              widget.points,
              _selectedIndex,
              Theme.of(context).colorScheme.primary,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _AdminWeightLineChartPainter extends CustomPainter {
  _AdminWeightLineChartPainter(this.points, this.selectedIndex, this.accent);

  final List<ExerciseWeightLogEntry> points;
  final int? selectedIndex;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 34.0;
    const rightPadding = 10.0;
    const topPadding = 12.0;
    const bottomPadding = 28.0;

    final chartRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      size.width - leftPadding - rightPadding,
      size.height - topPadding - bottomPadding,
    );

    final minWeight = points.map((p) => p.weightKg).reduce(math.min);
    final maxWeight = points.map((p) => p.weightKg).reduce(math.max);
    final range = (maxWeight - minWeight).abs() < 0.0001
        ? 1.0
        : (maxWeight - minWeight);

    final gridPaint = Paint()
      ..color = const Color(0xFF2D3546)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = chartRect.top + (chartRect.height * i / 4);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    for (var i = 0; i <= 3; i++) {
      final x = chartRect.left + (chartRect.width * i / 3);
      canvas.drawLine(
        Offset(x, chartRect.top),
        Offset(x, chartRect.bottom),
        gridPaint,
      );
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF8FA0B8)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(chartRect.left, chartRect.top),
      Offset(chartRect.left, chartRect.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(chartRect.left, chartRect.bottom),
      Offset(chartRect.right, chartRect.bottom),
      axisPaint,
    );

    Offset pointAt(int index) {
      final entry = points[index];
      final dx = points.length == 1
          ? chartRect.center.dx
          : chartRect.left + (chartRect.width * index / (points.length - 1));
      final normalized = (entry.weightKg - minWeight) / range;
      final dy = chartRect.bottom - (normalized * chartRect.height);
      return Offset(dx, dy);
    }

    final linePath = Path();
    final first = pointAt(0);
    linePath.moveTo(first.dx, first.dy);
    for (var i = 1; i < points.length; i++) {
      final p = pointAt(i);
      linePath.lineTo(p.dx, p.dy);
    }

    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = accent;
    for (var i = 0; i < points.length; i++) {
      if (i == selectedIndex) continue;
      canvas.drawCircle(pointAt(i), 4, dotPaint);
    }

    if (selectedIndex != null) {
      final p = pointAt(selectedIndex!);
      final selectedPaint = Paint()..color = Colors.white;
      canvas.drawCircle(p, 6, dotPaint);
      canvas.drawCircle(p, 3.2, selectedPaint);

      final entry = points[selectedIndex!];
      final value = entry.weightKg % 1 == 0
          ? entry.weightKg.toStringAsFixed(0)
          : entry.weightKg.toStringAsFixed(1);
      final tp = TextPainter(
        text: TextSpan(
          text: '$value kg',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bubbleWidth = tp.width + 14;
      const bubbleHeight = 24.0;
      var bubbleLeft = p.dx - bubbleWidth / 2;
      if (bubbleLeft < chartRect.left) bubbleLeft = chartRect.left;
      if (bubbleLeft + bubbleWidth > chartRect.right) {
        bubbleLeft = chartRect.right - bubbleWidth;
      }
      final bubbleTop = (p.dy - bubbleHeight - 10).clamp(
        2.0,
        size.height - 30.0,
      );

      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, bubbleHeight),
        const Radius.circular(12),
      );
      final bubblePaint = Paint()..color = accent;
      canvas.drawRRect(bubbleRect, bubblePaint);
      tp.paint(canvas, Offset(bubbleLeft + 7, bubbleTop + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _AdminWeightLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.accent != accent;
  }
}

class _UserDataTile extends StatelessWidget {
  const _UserDataTile({
    required this.label,
    required this.value,
    required this.icon,
    this.isWide = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isWide ? double.infinity : 136,
      child: Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.surfaceBorderFor(context),
            width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              value,
              maxLines: isWide ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initialsFromName(String value) {
  final parts = value.split(' ').where((item) => item.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isEmpty) {
    return '?';
  }
  return parts.first.substring(0, 1).toUpperCase();
}

String _formatDateLong(DateTime date) {
  return '${date.day} ${_kMonthNames[date.month - 1]} ${date.year}';
}

String _formatSecondsAsClock(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  final duration = Duration(seconds: safeSeconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _capitalize(String value) {
  return value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _RoutinesCatalogAdmin extends StatefulWidget {
  const _RoutinesCatalogAdmin({
    required this.routines,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });
  final List<_RoutineData> routines;
  final Future<void> Function() onAdd;
  final Future<void> Function(int index) onEdit;
  final void Function(int index) onDelete;

  @override
  State<_RoutinesCatalogAdmin> createState() => _RoutinesCatalogAdminState();
}

class _RoutinesCatalogAdminState extends State<_RoutinesCatalogAdmin> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterType = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({int index, _RoutineData data})> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final result = <({int index, _RoutineData data})>[];

    for (var i = 0; i < widget.routines.length; i++) {
      final r = widget.routines[i];
      final typeLabel = _trainingTypeLabel(r.trainingType).toLowerCase();

      if (q.isNotEmpty &&
          !r.name.toLowerCase().contains(q) &&
          !r.description.toLowerCase().contains(q) &&
          !typeLabel.contains(q)) {
        continue;
      }

      if (_filterType.isNotEmpty &&
          _trainingTypeLabel(r.trainingType) != _filterType) {
        continue;
      }

      result.add((index: i, data: r));
    }

    return result;
  }

  String _trainingTypeLabel(_RoutineTrainingType type) {
    switch (type) {
      case _RoutineTrainingType.mixed:
        return 'Mixta';
      case _RoutineTrainingType.circuit:
        return 'Circuito';
      case _RoutineTrainingType.reps:
        return 'Series/Reps';
      case _RoutineTrainingType.timed:
        return 'Tiempo';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar rutina...',
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                    size: 20,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _AdminDropdown(
                      value: _filterType.isEmpty ? null : _filterType,
                      hint: 'Todos los tipos',
                      items: const <String>[
                        'Mixta',
                        'Circuito',
                        'Series/Reps',
                        'Tiempo',
                      ],
                      onChanged: (v) => setState(() => _filterType = v ?? ''),
                    ),
                  ),
                  if (_filterType.isNotEmpty) ...[
                    SizedBox(width: 6),
                    IconButton(
                      onPressed: () => setState(() => _filterType = ''),
                      icon: Icon(
                        Icons.filter_alt_off_outlined,
                        size: 20,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${filtered.length} rutinas',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onAdd,
                    icon: Icon(Icons.add_rounded, size: 16),
                    label: Text('Crear rutina'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Sin resultados de rutinas.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => SizedBox(height: 10),
                  itemBuilder: (context, visibleIndex) {
                    final item = filtered[visibleIndex];
                    final index = item.index;
                    final r = item.data;
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.surfaceBorderFor(context),
                          width:
                              Theme.of(context).brightness == Brightness.light
                              ? 1.25
                              : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: IconButton(
                                  onPressed: () => widget.onEdit(index),
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: IconButton(
                                  onPressed: () =>
                                      _confirmDelete(context, index),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 13,
                                    color: Color(0xFF666666),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            ],
                          ),
                          if (r.description.isNotEmpty) ...[
                            SizedBox(height: 4),
                            Text(
                              r.description,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${r.exercises.length} ejercicios en la rutina',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Spacer(),
                              Text(
                                _trainingTypeLabel(r.trainingType),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.modalSurfaceFor(context),
        title: Text(
          'Eliminar rutina',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Eliminar "${widget.routines[index].name}"?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete(index);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogo editable (grid de tarjetas)
// ---------------------------------------------------------------------------

class _ExerciseCatalogAdmin extends StatefulWidget {
  const _ExerciseCatalogAdmin({
    required this.exercises,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
  });
  final List<ExerciseEntry> exercises;
  final Future<void> Function(int index) onEdit;
  final void Function(int index) onDelete;
  final Future<void> Function() onAdd;

  @override
  State<_ExerciseCatalogAdmin> createState() => _ExerciseCatalogAdminState();
}

class _ExerciseCatalogAdminState extends State<_ExerciseCatalogAdmin> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterCategory = '';
  String _filterEquipment = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<({int index, ExerciseEntry data})> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final result = <({int index, ExerciseEntry data})>[];
    for (var i = 0; i < widget.exercises.length; i++) {
      final e = widget.exercises[i];
      if (q.isNotEmpty &&
          !e.name.toLowerCase().contains(q) &&
          !e.description.toLowerCase().contains(q)) {
        continue;
      }
      if (_filterCategory.isNotEmpty && e.category != _filterCategory) {
        continue;
      }
      if (_filterEquipment.isNotEmpty &&
          !e.equipment.contains(_filterEquipment)) {
        continue;
      }
      result.add((index: i, data: e));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar ejercicio...',
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                    size: 20,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _AdminDropdown(
                      value: _filterCategory.isEmpty ? null : _filterCategory,
                      hint: 'Todas las categorias',
                      items: _kCategories,
                      onChanged: (v) =>
                          setState(() => _filterCategory = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AdminDropdown(
                      value: _filterEquipment.isEmpty ? null : _filterEquipment,
                      hint: 'Todo equipamiento',
                      items: _kEquipmentForm,
                      onChanged: (v) =>
                          setState(() => _filterEquipment = v ?? ''),
                    ),
                  ),
                  if (_filterCategory.isNotEmpty ||
                      _filterEquipment.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => setState(() {
                        _filterCategory = '';
                        _filterEquipment = '';
                      }),
                      icon: Icon(
                        Icons.filter_alt_off_outlined,
                        size: 20,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${filtered.length} ejercicios',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onAdd,
                    icon: Icon(Icons.add_rounded, size: 16),
                    label: Text('Añadir ejercicio'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Sin resultados',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _ExerciseCard(
                      exercise: item.data,
                      onEdit: () => widget.onEdit(item.index),
                      onDelete: () => _confirmDelete(context, item.index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.modalSurfaceFor(context),
        title: Text(
          'Eliminar ejercicio',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Eliminar "${widget.exercises[index].name}"?',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete(index);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown de filtro
// ---------------------------------------------------------------------------

class _AdminDropdown extends StatelessWidget {
  const _AdminDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });
  final String? value;
  final String hint;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: 0.68);
    final bool isActive = value != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isActive
            ? accent.withValues(alpha: 0.12)
            : onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? accent : AppTheme.surfaceBorderFor(context),
          width: isActive ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: TextStyle(color: muted, fontSize: 13)),
          isExpanded: true,
          dropdownColor: theme.colorScheme.surface,
          menuMaxHeight: 300,
          borderRadius: BorderRadius.circular(10),
          icon: AnimatedRotation(
            turns: 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isActive ? accent : muted,
              size: 20,
            ),
          ),
          style: TextStyle(
            color: isActive ? accent : onSurface,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          onChanged: onChanged,
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                hint,
                style: TextStyle(
                  color: muted,
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            ...items.map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  style: TextStyle(
                    color: e == value ? accent : onSurface,
                    fontWeight: e == value
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de ejercicio (estilo HTML: imagen + puntos + tags)
// ---------------------------------------------------------------------------

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.onEdit,
    required this.onDelete,
  });
  final ExerciseEntry exercise;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static Color _dotColor(String level) {
    switch (level) {
      case 'Principiante':
        return const Color(0xFF22C55E);
      case 'Intermedio':
        return const Color(0xFFFACC15);
      default:
        return Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat =
        _kCatColors[exercise.category] ??
        (
          bg: Color(0xFF2A2A2A),
          fg: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
        );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // imagen / placeholder
          Stack(
            children: [
              Container(
                height: 110,
                width: double.infinity,
                color: const Color(0xFF1A1A2E),
                child: exercise.imageBytes != null
                    ? Image.memory(exercise.imageBytes!, fit: BoxFit.cover)
                    : exercise.imageUrl.isNotEmpty
                    ? Image.network(
                        exercise.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, e, s) =>
                            const _ImgPlaceholder(),
                      )
                    : const _ImgPlaceholder(),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor(exercise.level),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
          // contenido
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          exercise.name,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          onPressed: onEdit,
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 13,
                            color: Color(0xFF666666),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                  if (exercise.description.isNotEmpty) ...[
                    SizedBox(height: 3),
                    Text(
                      exercise.description,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 11,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),
                  // tag categoria
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cat.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      exercise.category,
                      style: TextStyle(
                        color: cat.fg,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (exercise.equipment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: exercise.equipment
                          .take(2)
                          .map(
                            (e) => Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceBorderFor(context),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                e,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.fitness_center_outlined,
      color: Color(0xFF444466),
      size: 36,
    ),
  );
}

// ---------------------------------------------------------------------------
// Formulario de ejercicio (fiel al HTML)
// ---------------------------------------------------------------------------

class _ExerciseFormSheet extends StatefulWidget {
  const _ExerciseFormSheet({this.existing});
  final ExerciseEntry? existing;

  @override
  State<_ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends State<_ExerciseFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _tipsCtrl;
  late final TextEditingController _videoCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _otherMuscleCtrl;
  late final TextEditingController _otherEquipCtrl;

  late String _category;
  late String _level;
  late Set<String> _selectedMuscles;
  late Set<String> _selectedEquipment;
  late List<String> _customMuscles;
  late List<String> _customEquipment;
  Uint8List? _pickedImageBytes;
  String _pickedImageName = '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _tipsCtrl = TextEditingController(text: e?.tips ?? '');
    _videoCtrl = TextEditingController(text: e?.videoUrl ?? '');
    _imageUrlCtrl = TextEditingController(text: e?.imageUrl ?? '');
    _otherMuscleCtrl = TextEditingController();
    _otherEquipCtrl = TextEditingController();
    _category = e?.category ?? _kCategories.first;
    _level = e?.level ?? _kLevels.first;
    _selectedMuscles = Set<String>.from(e?.muscles ?? []);
    _selectedEquipment = Set<String>.from(e?.equipment ?? []);
    _customMuscles = (e?.muscles ?? [])
        .where((m) => !_kMuscles.contains(m))
        .toList();
    _customEquipment = (e?.equipment ?? [])
        .where((eq) => !_kEquipmentForm.contains(eq))
        .toList();
    _pickedImageBytes = e?.imageBytes;
    _pickedImageName = e?.imageName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tipsCtrl.dispose();
    _videoCtrl.dispose();
    _imageUrlCtrl.dispose();
    _otherMuscleCtrl.dispose();
    _otherEquipCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedImageBytes = bytes;
      _pickedImageName = picked.name;
    });
  }

  void _clearPickedImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageName = '';
    });
  }

  void _toggleMuscle(String m) => setState(() {
    if (!_selectedMuscles.remove(m)) _selectedMuscles.add(m);
  });
  void _toggleEquip(String eq) => setState(() {
    if (!_selectedEquipment.remove(eq)) _selectedEquipment.add(eq);
  });

  void _addCustomMuscle() {
    final v = _otherMuscleCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _customMuscles.add(v);
      _selectedMuscles.add(v);
      _otherMuscleCtrl.clear();
    });
  }

  void _addCustomEquip() {
    final v = _otherEquipCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _customEquipment.add(v);
      _selectedEquipment.add(v);
      _otherEquipCtrl.clear();
    });
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13),
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.red),
    ),
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Si hay imagen local, subirla a Cloudinary para que persista
    String imageUrl = _imageUrlCtrl.text.trim();
    Uint8List? imageBytes = _pickedImageBytes;
    if (_pickedImageBytes != null) {
      final uploaded = await CloudinaryService.uploadImageBytes(
        _pickedImageBytes!,
        fileName: _pickedImageName.isNotEmpty ? _pickedImageName : null,
      );
      if (uploaded != null) {
        imageUrl = uploaded;
        imageBytes = null; // Ya está en la nube, no hace falta guardar bytes
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      ExerciseEntry(
        name: _nameCtrl.text.trim(),
        category: _category,
        equipment: _selectedEquipment.toList(),
        level: _level,
        description: _descCtrl.text.trim(),
        muscles: _selectedMuscles.toList(),
        videoUrl: _videoCtrl.text.trim(),
        imageUrl: imageUrl,
        imageBytes: imageBytes,
        imageName: _pickedImageName,
        tips: _tipsCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.06),
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  isEdit ? 'Editar ejercicio' : 'Crear nuevo ejercicio',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppTheme.surfaceBorderFor(context), height: 1),
          // body
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FLabel('Nombre del ejercicio'),
                    TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Obligatorio'
                          : null,
                      decoration: _dec('Ej: Press banca'),
                    ),
                    const SizedBox(height: 14),
                    // Categoria + Dificultad en fila
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FLabel('Categoria'),
                              _FormDrop(
                                value: _category,
                                items: _kCategories,
                                onChanged: (v) =>
                                    setState(() => _category = v!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FLabel('Dificultad'),
                              _FormDrop(
                                value: _level,
                                items: _kLevels,
                                onChanged: (v) => setState(() => _level = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14),
                    _FLabel('Descripcion del ejercicio'),
                    TextFormField(
                      controller: _descCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      maxLines: 3,
                      decoration: _dec(
                        'Describe como realizar el ejercicio...',
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Grupos musculares
                    _FLabel('Grupos musculares'),
                    _ChipGroup(
                      allOptions: [..._kMuscles, ..._customMuscles],
                      selected: _selectedMuscles,
                      onToggle: _toggleMuscle,
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otherMuscleCtrl,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                            ),
                            decoration: _dec('Otro musculo...'),
                            onSubmitted: (_) => _addCustomMuscle(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _AddBtn(onTap: _addCustomMuscle),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Equipamiento
                    _FLabel('Equipamiento'),
                    _ChipGroup(
                      allOptions: [..._kEquipmentForm, ..._customEquipment],
                      selected: _selectedEquipment,
                      onToggle: _toggleEquip,
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otherEquipCtrl,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                            ),
                            decoration: _dec('Otro equipamiento...'),
                            onSubmitted: (_) => _addCustomEquip(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _AddBtn(onTap: _addCustomEquip),
                      ],
                    ),
                    SizedBox(height: 14),
                    _FLabel('URL del video (opcional)'),
                    TextField(
                      controller: _videoCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      decoration: _dec('https://youtube.com/...'),
                      keyboardType: TextInputType.url,
                    ),
                    SizedBox(height: 14),
                    _FLabel('Imagen del ejercicio'),
                    TextField(
                      controller: _imageUrlCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      decoration: _dec('URL de imagen (https://...)'),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    // Preview de la URL introducida (si no hay foto local)
                    if (_pickedImageBytes == null &&
                        _imageUrlCtrl.text.trim().isNotEmpty) ...[  
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _imageUrlCtrl.text.trim(),
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'URL no válida o sin acceso',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        border: Border.all(
                          color: _pickedImageBytes != null
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF2F2F2F),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: Icon(Icons.upload_file_rounded, size: 16),
                            label: Text('Subir foto'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // miniatura a la derecha
                          if (_pickedImageBytes != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _pickedImageBytes!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (_pickedImageName.isNotEmpty)
                            Expanded(
                              child: Text(
                                _pickedImageName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (_pickedImageBytes != null)
                            IconButton(
                              onPressed: _clearPickedImage,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14),
                    _FLabel('Consejos de ejecucion'),
                    TextField(
                      controller: _tipsCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      maxLines: 4,
                      decoration: _dec('Consejos importantes...'),
                    ),
                    SizedBox(height: 24),
                    Divider(color: AppTheme.surfaceBorderFor(context)),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.62),
                              side: const BorderSide(color: Color(0xFF333333)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Cerrar',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                              isEdit ? 'Guardar cambios' : 'Crear ejercicio',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip group (pills toggleables)
// ---------------------------------------------------------------------------

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.allOptions,
    required this.selected,
    required this.onToggle,
  });
  final List<String> allOptions;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: allOptions.map((opt) {
          final isActive = selected.contains(opt);
          return GestureDetector(
            onTap: () => onToggle(opt),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? Color(0xFF1F1105) : Color(0xFF0D0D0D),
                border: Border.all(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Color(0xFF333333),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                opt,
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Color(0xFFAAAAAA),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers visuales
// ---------------------------------------------------------------------------

class _FLabel extends StatelessWidget {
  const _FLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _AddBtn extends StatelessWidget {
  const _AddBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: const Text(
      'Anadir',
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

class _FormDrop extends StatelessWidget {
  const _FormDrop({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String value;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    dropdownColor: Theme.of(context).cardColor,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 13,
    ),
    icon: Icon(
      Icons.keyboard_arrow_down_rounded,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
      size: 18,
    ),
    decoration: InputDecoration(
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Color(0xFF2F2F2F)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Color(0xFF2F2F2F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    ),
    onChanged: onChanged,
    items: items
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList(),
  );
}

class _RoutineFormSheet extends StatefulWidget {
  const _RoutineFormSheet({this.existing});

  final _RoutineData? existing;

  @override
  State<_RoutineFormSheet> createState() => _RoutineFormSheetState();
}

class _RoutineFormSheetState extends State<_RoutineFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final List<_RoutineExerciseSpec> _selectedExercises = [];
  late final TextEditingController _roundsCtrl;
  _RoutineTrainingType _trainingType = _RoutineTrainingType.mixed;

  @override
  void initState() {
    super.initState();
    _roundsCtrl = TextEditingController(
      text: widget.existing?.rounds.toString() ?? '3',
    );
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _descCtrl.text = existing.description;
      _trainingType = existing.trainingType;
      _selectedExercises.addAll(
        existing.exercises
            .map(
              (s) => _RoutineExerciseSpec(
                exercise: s.exercise,
                type: s.type,
                restSeconds: s.restSeconds,
                workSeconds: s.workSeconds,
                sets: s.sets,
                reps: s.reps,
                weightKg: s.weightKg,
                showWeightField: s.showWeightField,
              ),
            )
            .toList(),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _roundsCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13),
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Future<void> _pickExercises() async {
    final currentNames = _selectedExercises.map((e) => e.exercise.name).toSet();
    final picked = await showModalBottomSheet<List<ExerciseEntry>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExercisePickerSheet(selectedNames: currentNames),
    );

    if (picked == null || !mounted) return;
    final defaultType =
        (_trainingType == _RoutineTrainingType.timed ||
            _trainingType == _RoutineTrainingType.circuit)
        ? _RoutineSpecType.time
        : _RoutineSpecType.setsReps;

    setState(() {
      for (final ex in picked) {
        final exists = _selectedExercises.any(
          (e) => e.exercise.name == ex.name,
        );
        if (!exists) {
          _selectedExercises.add(
            _RoutineExerciseSpec(
              exercise: ex,
              type: defaultType,
              workSeconds: defaultType == _RoutineSpecType.time ? 45 : null,
              restSeconds: defaultType == _RoutineSpecType.time ? 30 : 60,
              sets: defaultType == _RoutineSpecType.setsReps ? 4 : null,
              reps: defaultType == _RoutineSpecType.setsReps ? 12 : null,
            ),
          );
        }
      }
    });
  }

  Future<void> _configureExercise(int index) async {
    final result = await showModalBottomSheet<_RoutineExerciseSpec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoutineExerciseSpecSheet(
        spec: _selectedExercises[index],
        allowTypeChange: _trainingType == _RoutineTrainingType.mixed,
        forcedType: _trainingType == _RoutineTrainingType.mixed
            ? null
            : ((_trainingType == _RoutineTrainingType.timed ||
                      _trainingType == _RoutineTrainingType.circuit)
                  ? _RoutineSpecType.time
                  : _RoutineSpecType.setsReps),
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _selectedExercises[index] = result);
  }

  String _specResume(_RoutineExerciseSpec spec) {
    final weightTxt = spec.weightKg == null ? '' : ' | ${spec.weightKg} kg';
    if (spec.type == _RoutineSpecType.time) {
      final rest = spec.restSeconds ?? 0;
      final work = spec.workSeconds ?? 0;
      return 'Trabajo/Descanso: ${work}s / ${rest}s$weightTxt';
    }
    final restBetweenSets = spec.restSeconds ?? 60;
    return 'Series/Reps: ${spec.sets ?? '-'} x ${spec.reps ?? '-'} · Descanso: ${restBetweenSets}s$weightTxt';
  }

  void _saveRoutine() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Añade al menos un ejercicio a la rutina'),
        ),
      );
      return;
    }
    final preparedExercises = _selectedExercises.map((spec) {
      if (_trainingType == _RoutineTrainingType.timed ||
          _trainingType == _RoutineTrainingType.circuit) {
        return spec.copyWith(type: _RoutineSpecType.time);
      }
      if (_trainingType == _RoutineTrainingType.reps) {
        return spec.copyWith(
          type: _RoutineSpecType.setsReps,
          restSeconds: spec.restSeconds ?? 60,
        );
      }
      return spec;
    }).toList();

    Navigator.pop(
      context,
      _RoutineData(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        exercises: preparedExercises,
        trainingType: _trainingType,
        rounds: _trainingType == _RoutineTrainingType.circuit
            ? (int.tryParse(_roundsCtrl.text.trim()) ?? 3)
            : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.06),
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Editar Rutina' : 'Crear Rutina',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppTheme.surfaceBorderFor(context), height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FLabel('Nombre de la Rutina'),
                    TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Obligatorio'
                          : null,
                      decoration: _dec('Full Body 1'),
                    ),
                    const SizedBox(height: 10),
                    const _FLabel('Tipo de rutina'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Por tiempo'),
                          selected: _trainingType == _RoutineTrainingType.timed,
                          onSelected: (_) {
                            setState(() {
                              _trainingType = _RoutineTrainingType.timed;
                              for (
                                var i = 0;
                                i < _selectedExercises.length;
                                i++
                              ) {
                                final spec = _selectedExercises[i];
                                _selectedExercises[i] = spec.copyWith(
                                  type: _RoutineSpecType.time,
                                  workSeconds: spec.workSeconds ?? 45,
                                  restSeconds: spec.restSeconds ?? 30,
                                );
                              }
                            });
                          },
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22),
                          side: BorderSide(
                            color: _trainingType == _RoutineTrainingType.timed
                                ? Theme.of(context).colorScheme.primary
                                : Color(0xFF3A3A3A),
                          ),
                          labelStyle: TextStyle(
                            color: _trainingType == _RoutineTrainingType.timed
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('Por repeticiones'),
                          selected: _trainingType == _RoutineTrainingType.reps,
                          onSelected: (_) {
                            setState(() {
                              _trainingType = _RoutineTrainingType.reps;
                              for (
                                var i = 0;
                                i < _selectedExercises.length;
                                i++
                              ) {
                                final spec = _selectedExercises[i];
                                _selectedExercises[i] = spec.copyWith(
                                  type: _RoutineSpecType.setsReps,
                                  sets: spec.sets ?? 4,
                                  reps: spec.reps ?? 12,
                                  restSeconds: spec.restSeconds ?? 60,
                                );
                              }
                            });
                          },
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22),
                          side: BorderSide(
                            color: _trainingType == _RoutineTrainingType.reps
                                ? Theme.of(context).colorScheme.primary
                                : Color(0xFF3A3A3A),
                          ),
                          labelStyle: TextStyle(
                            color: _trainingType == _RoutineTrainingType.reps
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        ChoiceChip(
                          label: Text('Mixta'),
                          selected: _trainingType == _RoutineTrainingType.mixed,
                          onSelected: (_) {
                            setState(() {
                              _trainingType = _RoutineTrainingType.mixed;
                            });
                          },
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22),
                          side: BorderSide(
                            color: _trainingType == _RoutineTrainingType.mixed
                                ? Theme.of(context).colorScheme.primary
                                : Color(0xFF3A3A3A),
                          ),
                          labelStyle: TextStyle(
                            color: _trainingType == _RoutineTrainingType.mixed
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('Circuito'),
                          selected:
                              _trainingType == _RoutineTrainingType.circuit,
                          onSelected: (_) {
                            setState(() {
                              _trainingType = _RoutineTrainingType.circuit;
                              for (
                                var i = 0;
                                i < _selectedExercises.length;
                                i++
                              ) {
                                final spec = _selectedExercises[i];
                                _selectedExercises[i] = spec.copyWith(
                                  type: _RoutineSpecType.time,
                                  workSeconds: spec.workSeconds ?? 45,
                                  restSeconds: spec.restSeconds ?? 30,
                                );
                              }
                            });
                          },
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.22),
                          side: BorderSide(
                            color: _trainingType == _RoutineTrainingType.circuit
                                ? Theme.of(context).colorScheme.primary
                                : Color(0xFF3A3A3A),
                          ),
                          labelStyle: TextStyle(
                            color: _trainingType == _RoutineTrainingType.circuit
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (_trainingType == _RoutineTrainingType.circuit) ...[
                      SizedBox(height: 10),
                      _FLabel('Número de rondas'),
                      TextFormField(
                        controller: _roundsCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 1) return 'Mín. 1 ronda';
                          return null;
                        },
                        decoration: _dec('3'),
                      ),
                    ],
                    SizedBox(height: 14),
                    _FLabel('Descripcion (opcional)'),
                    TextFormField(
                      controller: _descCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      maxLines: 3,
                      decoration: _dec('Breve descripcion de la rutina...'),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _pickExercises,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text(
                          '+ Anadir Ejercicios',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    if (_selectedExercises.isEmpty)
                      Text(
                        'Todavia no has anadido ejercicios.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                          fontSize: 12,
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _selectedExercises.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _selectedExercises.removeAt(oldIndex);
                            _selectedExercises.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final spec = _selectedExercises[index];
                          final showWeight = spec.showWeightField;
                          return Container(
                            key: ValueKey('${spec.exercise.name}-$index'),
                            margin: EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppTheme.surfaceBorderFor(context),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              title: Text(
                                spec.exercise.name,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                _specResume(spec),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _WeightTrackingToggle(
                                    enabled: showWeight,
                                    onChanged: (next) => setState(() {
                                      _selectedExercises[index] =
                                          _selectedExercises[index].copyWith(
                                            showWeightField: next,
                                          );
                                    }),
                                  ),
                                  SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      Icons.tune_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 18,
                                    ),
                                    onPressed: () => _configureExercise(index),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.62),
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() {
                                      _selectedExercises.removeAt(index);
                                    }),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.62),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveRoutine,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          isEdit ? 'GUARDAR CAMBIOS' : 'GUARDAR RUTINA',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightTrackingToggle extends StatelessWidget {
  const _WeightTrackingToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Registrar peso durante el entrenamiento',
      child: GestureDetector(
        onTap: () => onChanged(!enabled),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 52,
          height: 28,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: enabled ? const Color(0xFFD97706) : const Color(0xFF444444),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF5A5A5A),
            ),
          ),
          child: Align(
            alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                size: 14,
                color: enabled
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF8C8C8C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinuteSecondDial extends StatelessWidget {
  const _MinuteSecondDial({
    required this.totalSeconds,
    required this.onChanged,
    this.compact = false,
    this.numberFontSize,
  });

  final int totalSeconds;
  final ValueChanged<int> onChanged;
  final bool compact;
  final double? numberFontSize;

  @override
  Widget build(BuildContext context) {
    final normalized = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (normalized ~/ 60).clamp(0, 59);
    final seconds = normalized % 60;

    Widget buildColumn({
      required int value,
      required int maxValue,
      required String label,
      required ValueChanged<int> onSelect,
    }) {
      return Expanded(
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            SizedBox(
              height: compact ? 74 : 92,
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                  initialItem: value,
                ),
                itemExtent: compact ? 24 : 30,
                diameterRatio: 1.3,
                selectionOverlay: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                      bottom: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                onSelectedItemChanged: onSelect,
                children: List.generate(maxValue + 1, (index) {
                  return Center(
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w700,
                        fontSize: numberFontSize ?? (compact ? 13 : 16),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(10, compact ? 6 : 8, 10, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.surfaceBorderFor(context),
          width: Theme.of(context).brightness == Brightness.light ? 1.25 : 1,
        ),
      ),
      child: Row(
        children: [
          buildColumn(
            value: minutes,
            maxValue: 59,
            label: 'Minutos',
            onSelect: (m) => onChanged((m * 60) + seconds),
          ),
          const SizedBox(width: 8),
          buildColumn(
            value: seconds,
            maxValue: 59,
            label: 'Segundos',
            onSelect: (s) => onChanged((minutes * 60) + s),
          ),
        ],
      ),
    );
  }
}

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({required this.selectedNames});
  final Set<String> selectedNames;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final Set<String> _pickedNames = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterCategory = '';

  @override
  void initState() {
    super.initState();
    _pickedNames.addAll(widget.selectedNames);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allExercises = ExerciseStore.instance.exercises;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredExercises = allExercises.where((ex) {
      final matchesQuery =
          query.isEmpty ||
          ex.name.toLowerCase().contains(query) ||
          ex.description.toLowerCase().contains(query);
      final matchesCategory =
          _filterCategory.isEmpty || ex.category == _filterCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Seleccionar ejercicios',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar ejercicio...',
                hintStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  size: 18,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: DropdownButtonFormField<String>(
              initialValue: _filterCategory.isEmpty ? null : _filterCategory,
              dropdownColor: Theme.of(context).cardColor,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                size: 18,
              ),
              decoration: InputDecoration(
                labelText: 'Musculo/Categoria',
                labelStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFF2F2F2F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Todas las categorias'),
                ),
                ..._kCategories.map(
                  (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _filterCategory = value ?? ''),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              itemCount: filteredExercises.length,
              itemBuilder: (_, i) {
                final ex = filteredExercises[i];
                final checked = _pickedNames.contains(ex.name);
                final alreadyInRoutine =
                    widget.selectedNames.contains(ex.name) && !checked;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          if (checked) {
                            _pickedNames.remove(ex.name);
                          } else {
                            _pickedNames.add(ex.name);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 140),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: checked
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.12)
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: checked
                                ? const Color(0xFFD97706)
                                : AppTheme.surfaceBorderFor(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex.name,
                                    style: TextStyle(
                                      color: alreadyInRoutine
                                          ? Color(0xFF22C55E)
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    alreadyInRoutine
                                        ? '${ex.category} · Ya añadido'
                                        : ex.category,
                                    style: TextStyle(
                                      color: alreadyInRoutine
                                          ? Color(
                                              0xFF22C55E,
                                            ).withValues(alpha: 0.7)
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.62),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              checked
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: checked
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF5A5A5A),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final selected = allExercises
                      .where((e) => _pickedNames.contains(e.name))
                      .toList();
                  Navigator.pop(context, selected);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Anadir seleccionados',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineExerciseSpecSheet extends StatefulWidget {
  const _RoutineExerciseSpecSheet({
    required this.spec,
    required this.allowTypeChange,
    this.forcedType,
  });

  final _RoutineExerciseSpec spec;
  final bool allowTypeChange;
  final _RoutineSpecType? forcedType;

  @override
  State<_RoutineExerciseSpecSheet> createState() =>
      _RoutineExerciseSpecSheetState();
}

class _RoutineExerciseSpecSheetState extends State<_RoutineExerciseSpecSheet> {
  late _RoutineSpecType _type;
  late final TextEditingController _restSecondsCtrl;
  late final TextEditingController _workSecondsCtrl;
  late final TextEditingController _setsCtrl;
  late final TextEditingController _repsCtrl;
  late final TextEditingController _weightCtrl;
  late int _restBetweenSetsSeconds;
  late int _timeWorkSeconds;
  late int _timeRestSeconds;

  @override
  void initState() {
    super.initState();
    _type = widget.forcedType ?? widget.spec.type;
    _restSecondsCtrl = TextEditingController(
      text: widget.spec.restSeconds?.toString() ?? '',
    );
    _workSecondsCtrl = TextEditingController(
      text: widget.spec.workSeconds?.toString() ?? '',
    );
    _setsCtrl = TextEditingController(text: widget.spec.sets?.toString() ?? '');
    _repsCtrl = TextEditingController(text: widget.spec.reps?.toString() ?? '');
    _weightCtrl = TextEditingController(
      text: widget.spec.weightKg?.toString() ?? '',
    );
    _restBetweenSetsSeconds = widget.spec.restSeconds ?? 60;
    _timeWorkSeconds = widget.spec.workSeconds ?? 45;
    _timeRestSeconds = widget.spec.restSeconds ?? 30;
    if (_restSecondsCtrl.text.trim().isEmpty) {
      _restSecondsCtrl.text = _restBetweenSetsSeconds.toString();
    }
    if (_workSecondsCtrl.text.trim().isEmpty) {
      _workSecondsCtrl.text = _timeWorkSeconds.toString();
    }
  }

  @override
  void dispose() {
    _restSecondsCtrl.dispose();
    _workSecondsCtrl.dispose();
    _setsCtrl.dispose();
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Color(0xFF4A4A4A), fontSize: 13),
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Color(0xFF2F2F2F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
    ),
  );

  void _save() {
    final rest = int.tryParse(_restSecondsCtrl.text.trim());
    final work = int.tryParse(_workSecondsCtrl.text.trim());
    final sets = int.tryParse(_setsCtrl.text.trim());
    final reps = int.tryParse(_repsCtrl.text.trim());
    final weight = double.tryParse(
      _weightCtrl.text.trim().replaceAll(',', '.'),
    );

    final updated = widget.spec.copyWith(
      type: _type,
      restSeconds: _type == _RoutineSpecType.time
          ? (rest ?? 30)
          : _restBetweenSetsSeconds,
      workSeconds: _type == _RoutineSpecType.time ? (work ?? 45) : null,
      sets: _type == _RoutineSpecType.time
          ? (sets ?? 1)
          : _type == _RoutineSpecType.setsReps
          ? (sets ?? 4)
          : null,
      reps: _type == _RoutineSpecType.setsReps ? (reps ?? 12) : null,
      weightKg: weight,
    );
    Navigator.pop(context, updated);
  }

  void _selectAll(TextEditingController controller) {
    if (controller.text.isEmpty) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560),
        child: Container(
          margin: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.2,
          ),
          decoration: BoxDecoration(
            color: AppTheme.modalSurfaceFor(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.spec.exercise.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.surfaceBorderFor(context),
                          width:
                              Theme.of(context).brightness == Brightness.light
                              ? 1.25
                              : 1,
                        ),
                      ),
                      child: widget.allowTypeChange
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setState(
                                    () => _type = _RoutineSpecType.time,
                                  ),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _type == _RoutineSpecType.time
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Tiempo',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _type == _RoutineSpecType.time
                                            ? Colors.black
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.62),
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setState(
                                    () => _type = _RoutineSpecType.setsReps,
                                  ),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _type == _RoutineSpecType.setsReps
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Series/Reps',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            _type == _RoutineSpecType.setsReps
                                            ? Colors.black
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.62),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                _type == _RoutineSpecType.time
                                    ? 'Tiempo (bloqueado por rutina)'
                                    : 'Series/Reps (bloqueado por rutina)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                ),
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_type == _RoutineSpecType.time)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FLabel('Trabajo'),
                                _MinuteSecondDial(
                                  totalSeconds: _timeWorkSeconds,
                                  compact: true,
                                  onChanged: (nextSeconds) {
                                    setState(() {
                                      _timeWorkSeconds = nextSeconds;
                                      _workSecondsCtrl.text = nextSeconds
                                          .toString();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FLabel('Descanso'),
                                _MinuteSecondDial(
                                  totalSeconds: _timeRestSeconds,
                                  compact: true,
                                  onChanged: (nextSeconds) {
                                    setState(() {
                                      _timeRestSeconds = nextSeconds;
                                      _restSecondsCtrl.text = nextSeconds
                                          .toString();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _FLabel('Series (opcional)'),
                      TextField(
                        controller: _setsCtrl,
                        onTap: () => _selectAll(_setsCtrl),
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: _dec('Ej: 3  (dejar vacío = 1 serie)'),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FLabel('Series'),
                                TextField(
                                  controller: _setsCtrl,
                                  onTap: () => _selectAll(_setsCtrl),
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  decoration: _dec('Ej: 4'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FLabel('Repeticiones'),
                                TextField(
                                  controller: _repsCtrl,
                                  onTap: () => _selectAll(_repsCtrl),
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  decoration: _dec('Ej: 12'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _FLabel('Descanso entre series'),
                      _MinuteSecondDial(
                        totalSeconds: _restBetweenSetsSeconds,
                        compact: true,
                        numberFontSize: 16,
                        onChanged: (nextSeconds) {
                          setState(() {
                            _restBetweenSetsSeconds = nextSeconds;
                            _restSecondsCtrl.text = nextSeconds.toString();
                          });
                        },
                      ),
                    ],
                  ),
                SizedBox(height: 12),
                _FLabel('Peso (opcional)'),
                TextField(
                  controller: _weightCtrl,
                  onTap: () => _selectAll(_weightCtrl),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: _dec('Ej: 20'),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Guardar ejercicio',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

