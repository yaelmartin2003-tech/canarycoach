import 'package:flutter/foundation.dart';

enum WorkoutExerciseMode { timed, reps }

enum WorkoutRoutineKind { timed, reps, mixed, circuit }

class WorkoutRoutineExercise {
  const WorkoutRoutineExercise({
    required this.name,
    this.mode = WorkoutExerciseMode.timed,
    this.durationSeconds = 180,
    this.restSeconds = 20,
    this.sets,
    this.reps,
    this.weightKg,
    this.showWeightField = false,
  });

  final String name;
  final WorkoutExerciseMode mode;
  final int durationSeconds;
  final int restSeconds;
  final int? sets;
  final int? reps;
  final double? weightKg;
  final bool showWeightField;
}

class WorkoutRoutine {
  const WorkoutRoutine({
    required this.name,
    required this.description,
    required this.exercises,
    this.kind = WorkoutRoutineKind.mixed,
    this.rounds = 1,
  });

  final String name;
  final String description;
  final List<WorkoutRoutineExercise> exercises;
  final WorkoutRoutineKind kind;
  final int rounds;
}

class WorkoutRoutineStore extends ChangeNotifier {
  WorkoutRoutineStore._();

  static final WorkoutRoutineStore instance = WorkoutRoutineStore._();

  final List<WorkoutRoutine> _routines = [];

  List<WorkoutRoutine> get routines => List.unmodifiable(_routines);

  WorkoutRoutine? byName(String name) {
    for (final routine in _routines) {
      if (routine.name == name) return routine;
    }
    return null;
  }

  void replaceAll(List<WorkoutRoutine> routines) {
    _routines
      ..clear()
      ..addAll(routines);
    notifyListeners();
  }

  /// Renombra [oldName] → [newName] en los ejercicios de todas las rutinas.
  /// Se llama al editar el nombre de un ejercicio del catálogo.
  void renameExerciseInAllRoutines(String oldName, String newName) {
    if (oldName == newName) return;
    var changed = false;
    for (var i = 0; i < _routines.length; i++) {
      final routine = _routines[i];
      final updatedExercises = routine.exercises.map((ex) {
        if (ex.name != oldName) return ex;
        changed = true;
        return WorkoutRoutineExercise(
          name: newName,
          mode: ex.mode,
          durationSeconds: ex.durationSeconds,
          restSeconds: ex.restSeconds,
          sets: ex.sets,
          reps: ex.reps,
          weightKg: ex.weightKg,
          showWeightField: ex.showWeightField,
        );
      }).toList();
      if (changed) {
        _routines[i] = WorkoutRoutine(
          name: routine.name,
          description: routine.description,
          exercises: updatedExercises,
          kind: routine.kind,
          rounds: routine.rounds,
        );
      }
    }
    if (changed) notifyListeners();
  }
}
