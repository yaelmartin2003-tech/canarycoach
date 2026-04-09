import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../data/exercise_store.dart';
import '../../data/user_store.dart';
import '../../data/workout_routine_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/countdown_beeper.dart';

enum _SessionPhase { idle, preparing, workout, rest, finished }

class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    required this.routineName,
    required this.forDate,
  });

  final String routineName;
  final DateTime forDate;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  static const int _prepareSeconds = 10;

  Timer? _ticker;
  _SessionPhase _phase = _SessionPhase.idle;

  late final WorkoutRoutine _routine;
  int _currentExerciseIndex = 0;
  int _currentSetIndex = 0;
  int _exerciseRemainingSeconds = 0;
  int _totalElapsedSeconds = 0;
  bool _isPaused = false;
  bool _isTimerPanelMinimized = false;
  bool _resumeAfterPreparation = false;
  bool _isRestFromRepExercise = false;

  // Ronda actual (solo relevante para rutinas tipo Circuito)
  int _currentRound = 0;
  bool _hasCheckpoint = false;
  _SessionPhase _savedPhase = _SessionPhase.workout;
  int _savedExerciseIndex = 0;
  int _savedSetIndex = 0;
  int _savedRound = 0;
  int _savedExerciseRemainingSeconds = 0;
  int _savedTotalElapsedSeconds = 0;
  final Map<String, double> _enteredWeightsByExercise = <String, double>{};
  bool _inlineTimedOpen = true;

  @override
  void initState() {
    super.initState();
    _routine =
        WorkoutRoutineStore.instance.byName(widget.routineName) ??
        _fallbackRoutine(widget.routineName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startSession(fromGesture: false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  WorkoutRoutineExercise get _currentExercise =>
      _routine.exercises[_currentExerciseIndex];

  bool get _isSessionRunning =>
      _phase == _SessionPhase.preparing ||
      _phase == _SessionPhase.workout ||
      _phase == _SessionPhase.rest;

  bool get _currentExerciseIsTimed {
    if (_phase != _SessionPhase.workout) return true;
    return _currentExercise.mode == WorkoutExerciseMode.timed;
  }

  int get _nextWorkTargetSeconds {
    if (_currentExerciseIndex >= _routine.exercises.length - 1) return 0;
    return _initialExerciseSeconds(
      _routine.exercises[_currentExerciseIndex + 1],
    );
  }

  bool get _resumeTargetIsWorkout {
    if (_resumeAfterPreparation && _hasCheckpoint) {
      return _savedPhase == _SessionPhase.workout;
    }
    return true;
  }

  int get _resumeTargetSeconds {
    if (_resumeAfterPreparation && _hasCheckpoint) {
      return _savedExerciseRemainingSeconds;
    }
    return _initialExerciseSeconds(_routine.exercises[_currentExerciseIndex]);
  }

  String get _primaryTimerLabel {
    if (_phase == _SessionPhase.preparing) return 'PREPARATE';
    if (_phase == _SessionPhase.rest) return 'DESCANSAR';
    return 'ENTRENAR';
  }

  int get _primaryTimerSeconds {
    if (_phase == _SessionPhase.preparing) return _exerciseRemainingSeconds;
    if (_phase == _SessionPhase.rest) return _exerciseRemainingSeconds;
    if (_currentExerciseIsTimed) return _exerciseRemainingSeconds;
    return _totalElapsedSeconds;
  }

  Color get _primaryTimerColor {
    if (_phase == _SessionPhase.preparing) return const Color(0xFFEAF45A);
    if (_phase == _SessionPhase.rest) return const Color(0xFFE34A3B);
    return const Color(0xFFA6F35E);
  }

  Color get _primaryTimerTextColor {
    if (_phase == _SessionPhase.rest) return const Color(0xFFF2F2F2);
    return Colors.black;
  }

  String get _secondaryTimerLabel {
    if (_phase == _SessionPhase.preparing) {
      return _resumeTargetIsWorkout ? 'ENTRENAR' : 'DESCANSAR';
    }
    if (_phase == _SessionPhase.rest) return 'ENTRENAR';
    return 'DESCANSAR';
  }

  int get _secondaryTimerSeconds {
    if (_phase == _SessionPhase.preparing) {
      return _resumeTargetSeconds;
    }
    if (_phase == _SessionPhase.rest) return _nextWorkTargetSeconds;
    return _currentExercise.restSeconds;
  }

  Color get _secondaryTimerColor {
    if (_phase == _SessionPhase.preparing) {
      return _resumeTargetIsWorkout
          ? const Color(0xFFA6F35E)
          : const Color(0xFFE34A3B);
    }
    if (_phase == _SessionPhase.rest) return const Color(0xFFA6F35E);
    return const Color(0xFFE34A3B);
  }

  Color get _secondaryTimerTextColor {
    if (_phase == _SessionPhase.preparing) {
      return _resumeTargetIsWorkout ? Colors.black : const Color(0xFFF2F2F2);
    }
    if (_phase == _SessionPhase.rest) return Colors.black;
    return const Color(0xFFF2F2F2);
  }

  void _saveCheckpointFromCurrent() {
    _hasCheckpoint = true;
    _savedPhase = _phase;
    _savedExerciseIndex = _currentExerciseIndex;
    _savedSetIndex = _currentSetIndex;
    _savedRound = _currentRound;
    _savedExerciseRemainingSeconds = _exerciseRemainingSeconds;
    _savedTotalElapsedSeconds = _totalElapsedSeconds;
  }

  void _startSession({bool fromGesture = true}) {
    if (fromGesture) primeAudioContext();
    if (_hasCheckpoint) {
      final checkEx = _routine.exercises[_savedExerciseIndex];
      final skipPrep = checkEx.mode == WorkoutExerciseMode.reps;
      setState(() {
        _currentExerciseIndex = _savedExerciseIndex;
        _currentSetIndex = _savedSetIndex;
        _currentRound = _savedRound;
        _isPaused = false;
        _isTimerPanelMinimized = false;
        if (skipPrep) {
          _phase = _savedPhase;
          _exerciseRemainingSeconds = _savedExerciseRemainingSeconds;
          _totalElapsedSeconds = _savedTotalElapsedSeconds;
          _resumeAfterPreparation = false;
          _isRestFromRepExercise = _savedPhase == _SessionPhase.rest;
        } else {
          _phase = _SessionPhase.preparing;
          _exerciseRemainingSeconds = _prepareSeconds;
          _resumeAfterPreparation = true;
        }
      });
      _startTickerIfNeeded();
      return;
    }

    final firstEx = _routine.exercises[0];
    final skipPrepFirst = firstEx.mode == WorkoutExerciseMode.reps;
    setState(() {
      _currentExerciseIndex = 0;
      _currentSetIndex = 0;
      _currentRound = 0;
      _totalElapsedSeconds = 0;
      _isPaused = false;
      _isTimerPanelMinimized = false;
      _resumeAfterPreparation = false;
      if (skipPrepFirst) {
        _phase = _SessionPhase.workout;
        _exerciseRemainingSeconds = 0;
      } else {
        _phase = _SessionPhase.preparing;
        _exerciseRemainingSeconds = _prepareSeconds;
      }
    });
    _startTickerIfNeeded();
  }

  int _initialExerciseSeconds(WorkoutRoutineExercise exercise) {
    if (exercise.mode == WorkoutExerciseMode.timed) {
      return (exercise.durationSeconds <= 0 ? 60 : exercise.durationSeconds);
    }
    return 0;
  }

  void _playCountdownBeepIfNeeded({
    required int previousSeconds,
    required int currentSeconds,
  }) {
    if (currentSeconds >= 1 && currentSeconds <= 3) {
      // Pitido exactamente en 3, 2 y 1.
      playCountdownBeep(isFinal: false);
    }
    if (previousSeconds > 0 && currentSeconds == 0) {
      // Señal final más marcada al terminar el temporizador.
      playCountdownFinishBeep();
    }
  }

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isPaused || !_isSessionRunning) return;

      setState(() {
        _totalElapsedSeconds += 1;

        if (_phase == _SessionPhase.preparing) {
          if (_exerciseRemainingSeconds > 0) {
            final previous = _exerciseRemainingSeconds;
            _exerciseRemainingSeconds -= 1;
            _playCountdownBeepIfNeeded(
              previousSeconds: previous,
              currentSeconds: _exerciseRemainingSeconds,
            );
          }
          if (_exerciseRemainingSeconds == 0) {
            if (_resumeAfterPreparation && _hasCheckpoint) {
              _currentExerciseIndex = _savedExerciseIndex;
              _currentSetIndex = _savedSetIndex;
              _totalElapsedSeconds = _savedTotalElapsedSeconds;
              _phase = _savedPhase;
              _exerciseRemainingSeconds = _savedExerciseRemainingSeconds;
              _resumeAfterPreparation = false;
            } else {
              _phase = _SessionPhase.workout;
              _exerciseRemainingSeconds = _initialExerciseSeconds(
                _routine.exercises[_currentExerciseIndex],
              );
              _inlineTimedOpen = true;
            }
          }
          return;
        }

        if (_phase == _SessionPhase.workout &&
            _currentExercise.mode == WorkoutExerciseMode.timed) {
          if (_exerciseRemainingSeconds > 0) {
            final previous = _exerciseRemainingSeconds;
            _exerciseRemainingSeconds -= 1;
            _playCountdownBeepIfNeeded(
              previousSeconds: previous,
              currentSeconds: _exerciseRemainingSeconds,
            );
          }
          if (_exerciseRemainingSeconds == 0) {
            _moveToRestOrNext();
          }
          return;
        }

        if (_phase == _SessionPhase.rest) {
          if (_exerciseRemainingSeconds > 0) {
            final previous = _exerciseRemainingSeconds;
            _exerciseRemainingSeconds -= 1;
            _playCountdownBeepIfNeeded(
              previousSeconds: previous,
              currentSeconds: _exerciseRemainingSeconds,
            );
          }
          if (_exerciseRemainingSeconds == 0) {
            _moveToNextExerciseOrFinish();
          }
        }
      });
    });
  }

  void _completeCurrentRepExercise() {
    if (!_isSessionRunning || _phase != _SessionPhase.workout) return;
    if (_currentExercise.mode != WorkoutExerciseMode.reps) return;
    setState(_moveToRestOrNext);
  }

  /// Llamado cuando el usuario pulsa el chip naranja de descanso en un
  /// ejercicio por repeticiones. Inicia directamente la fase de descanso
  /// sin mostrar la cuenta atr�s de preparaci�n.
  void _startRestForRepExercise() {
    if (!_isSessionRunning) return;
    if (_phase != _SessionPhase.workout) return;
    if (_currentExercise.mode != WorkoutExerciseMode.reps) return;
    final restSeconds = _currentExercise.restSeconds;
    setState(() {
      _isTimerPanelMinimized = false;
      if (restSeconds > 0) {
        _isRestFromRepExercise = true;
        _phase = _SessionPhase.rest;
        _exerciseRemainingSeconds = restSeconds;
      } else {
        _isRestFromRepExercise = false;
        _advanceSetOrExercise();
      }
    });
  }

  void _moveToRestOrNext() {
    final restSeconds = _currentExercise.restSeconds;
    if (restSeconds > 0) {
      _phase = _SessionPhase.rest;
      _exerciseRemainingSeconds = restSeconds;
      return;
    }
    _advanceSetOrExercise();
  }

  void _moveToNextExerciseOrFinish() {
    _isRestFromRepExercise = false;
    _advanceSetOrExercise();
  }

  void _advanceSetOrExercise() {
    final exercise = _currentExercise;
    final totalSets = exercise.sets ?? 1;
    final isLastSet = _currentSetIndex >= totalSets - 1;

    if (!isLastSet) {
      // Quedan series del mismo ejercicio ? volvemos a workout.
      _currentSetIndex += 1;
      _phase = _SessionPhase.workout;
      _exerciseRemainingSeconds = _initialExerciseSeconds(exercise);
      _inlineTimedOpen = true;
      return;
    }

    // Todas las series completadas ? siguiente ejercicio.
    _currentSetIndex = 0;
    if (_currentExerciseIndex < _routine.exercises.length - 1) {
      _currentExerciseIndex += 1;
      _phase = _SessionPhase.workout;
      _exerciseRemainingSeconds = _initialExerciseSeconds(
        _routine.exercises[_currentExerciseIndex],
      );
      _inlineTimedOpen = true;
      return;
    }

    // �ltimo ejercicio completado. Circuito: comprobar rondas.
    if (_routine.kind == WorkoutRoutineKind.circuit &&
        _currentRound < _routine.rounds - 1) {
      _currentRound += 1;
      _currentExerciseIndex = 0;
      _phase = _SessionPhase.workout;
      _exerciseRemainingSeconds = _initialExerciseSeconds(
        _routine.exercises[0],
      );
      _inlineTimedOpen = true;
      return;
    }

    _phase = _SessionPhase.finished;
    _exerciseRemainingSeconds = 0;
    _ticker?.cancel();
    _isTimerPanelMinimized = false;
    _hasCheckpoint = false;
  }

  ExerciseEntry? _exerciseMetaFor(String name) {
    try {
      return ExerciseStore.instance.exercises.firstWhere(
        (item) => item.name == name,
      );
    } catch (_) {
      return null;
    }
  }

  void _openExerciseDetails(WorkoutRoutineExercise exercise) {
    final meta = _exerciseMetaFor(exercise.name);
    if (meta == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay detalle disponible para este ejercicio.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrainingExerciseDetailSheet(item: meta),
    );
  }

  Future<void> _openFinishSheet({required bool completed}) async {
    final result = await showModalBottomSheet<_SessionFeedbackResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SessionFeedbackSheet(),
    );

    if (result == null || !mounted) return;

    if (completed) {
      UserStore.instance.markCurrentUserWorkoutCompleted(
        routineName: widget.routineName,
        date: widget.forDate,
        totalSeconds: _totalElapsedSeconds,
        rating: result.rating,
      );
      final persistedNames = <String>{};
      for (final exercise in _routine.exercises) {
        if (!exercise.showWeightField) continue;
        if (persistedNames.contains(exercise.name)) continue;
        final entered = _enteredWeightsByExercise[exercise.name];
        if (entered == null || entered <= 0) continue;
        UserStore.instance.addCurrentUserExerciseWeight(
          exerciseName: exercise.name,
          weightKg: entered,
          date: DateTime.now(),
        );
        persistedNames.add(exercise.name);
      }
    }

    final feedbackText = result.comment.trim().isEmpty
        ? 'Valoracion guardada: ${result.rating} estrellas.'
        : 'Valoracion guardada: ${result.rating} estrellas. Sugerencia registrada.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(feedbackText)));

    Navigator.of(context).pop(true);
  }

  void _onTapFinish() {
    final canComplete =
        _isSessionRunning ||
        _phase == _SessionPhase.finished ||
        _totalElapsedSeconds > 0;
    if (!canComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia el entrenamiento antes de finalizarlo.'),
        ),
      );
      return;
    }
    _openFinishSheet(completed: true);
  }

  void _closeSession() {
    _ticker?.cancel();
    setState(() {
      if (_phase == _SessionPhase.preparing) {
        if (!_resumeAfterPreparation) {
          _hasCheckpoint = true;
          _savedPhase = _SessionPhase.workout;
          _savedExerciseIndex = _currentExerciseIndex;
          _savedSetIndex = _currentSetIndex;
          _savedRound = _currentRound;
          _savedExerciseRemainingSeconds = _initialExerciseSeconds(
            _routine.exercises[_currentExerciseIndex],
          );
          _savedTotalElapsedSeconds = _totalElapsedSeconds;
        }
      } else if (_isSessionRunning || _phase == _SessionPhase.finished) {
        _saveCheckpointFromCurrent();
      }
      _phase = _SessionPhase.idle;
      _isPaused = false;
      _isTimerPanelMinimized = false;
      _resumeAfterPreparation = false;
      _isRestFromRepExercise = false;
      // _currentSetIndex se restaura al reabrir via checkpoint (_savedSetIndex)
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBackgroundFor(context),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _HeroHeader(
                        routineName: _routine.name,
                        exerciseCount: _routine.exercises.length,
                        routineKind: _routine.kind,
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 12,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: Theme.of(context).colorScheme.onSurface,
                                size: 20,
                              ),
                            ),
                        ),
                      ),
                    ],
                  ),
                  ...List.generate(_routine.exercises.length, (index) {
                    final exercise = _routine.exercises[index];
                    final isCurrent =
                        _isSessionRunning && index == _currentExerciseIndex;
                    final isDone = _phase == _SessionPhase.finished
                        ? true
                        : index < _currentExerciseIndex;
                    final meta = _exerciseMetaFor(exercise.name);
                    final isRestActive =
                        _isSessionRunning &&
                        _phase == _SessionPhase.rest &&
                        index == _currentExerciseIndex;
                    final isWorkActive =
                        _isSessionRunning &&
                        _phase == _SessionPhase.workout &&
                        exercise.mode == WorkoutExerciseMode.timed &&
                        index == _currentExerciseIndex;
                    return _ExerciseCard(
                      index: index,
                      exercise: exercise,
                      exerciseInfo: meta,
                      isCurrent: isCurrent,
                      isDone: isDone,
                      enteredWeightKg: _enteredWeightsByExercise[exercise.name],
                      onWeightChanged: (value) {
                        if (value == null || value <= 0) {
                          _enteredWeightsByExercise.remove(exercise.name);
                        } else {
                          _enteredWeightsByExercise[exercise.name] = value;
                        }
                        setState(() {});
                      },
                      onTap: () => _openExerciseDetails(exercise),
                      onRestTap:
                          exercise.mode == WorkoutExerciseMode.reps &&
                              _isSessionRunning &&
                              index == _currentExerciseIndex &&
                              _phase == _SessionPhase.workout
                          ? _startRestForRepExercise
                          : null,
                      isRestActive: isRestActive,
                      restRemainingSeconds:
                          isRestActive ? _exerciseRemainingSeconds : 0,
                      totalRestSeconds: exercise.restSeconds,
                      isRestPaused: _isPaused,
                      onPauseRestTap: isRestActive
                          ? () {
                              setState(() {
                                _isPaused = !_isPaused;
                                _saveCheckpointFromCurrent();
                              });
                            }
                          : null,
                      isWorkActive: isWorkActive,
                      workRemainingSeconds:
                          isWorkActive ? _exerciseRemainingSeconds : 0,
                      totalWorkSeconds: exercise.durationSeconds,
                      isInlineTimedOpen: isWorkActive && _inlineTimedOpen,
                      onTimedChipTap: exercise.mode ==
                                  WorkoutExerciseMode.timed &&
                              _isSessionRunning &&
                              index == _currentExerciseIndex
                          ? () => setState(
                              () => _inlineTimedOpen = !_inlineTimedOpen,
                            )
                          : null,
                    );
                  }),
                  if (_phase == _SessionPhase.finished)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: _CompletionCard(
                        totalSeconds: _totalElapsedSeconds,
                        onFinish: _onTapFinish,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  WorkoutRoutine _fallbackRoutine(String routineName) {
    return WorkoutRoutine(
      name: routineName,
      description: 'Rutina asignada por tu coach.',
      kind: WorkoutRoutineKind.mixed,
      exercises: const [
        WorkoutRoutineExercise(
          name: 'Calentamiento',
          mode: WorkoutExerciseMode.timed,
          durationSeconds: 120,
          restSeconds: 20,
        ),
        WorkoutRoutineExercise(
          name: 'Circuito principal',
          mode: WorkoutExerciseMode.reps,
          sets: 4,
          reps: 12,
          restSeconds: 30,
        ),
        WorkoutRoutineExercise(
          name: 'Vuelta a la calma',
          mode: WorkoutExerciseMode.timed,
          durationSeconds: 120,
          restSeconds: 0,
        ),
      ],
    );
  }

  static String _mmss(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.routineName,
    required this.exerciseCount,
    required this.routineKind,
  });

  final String routineName;
  final int exerciseCount;
  final WorkoutRoutineKind routineKind;

  String get _kindLabel => switch (routineKind) {
    WorkoutRoutineKind.timed => 'Por tiempo',
    WorkoutRoutineKind.reps => 'Por reps',
    WorkoutRoutineKind.mixed => 'Mixta',
    WorkoutRoutineKind.circuit => 'Circuito',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/portada_entrenamientos.jpg', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.78),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 8,
              20,
              24,
            ),
              child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENTRENAMIENTO DE HOY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  routineName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$exerciseCount ejercicios · $_kindLabel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
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


class _StartButton extends StatelessWidget {
  const _StartButton({required this.onPressed, required this.isResume});

  final VoidCallback onPressed;
  final bool isResume;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 28),
        label: Text(isResume ? 'CONTINUAR' : 'EMPEZAR'),
      ),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    required this.index,
    required this.exercise,
    required this.exerciseInfo,
    required this.isCurrent,
    required this.isDone,
    required this.onTap,
    this.enteredWeightKg,
    this.onWeightChanged,
    this.onRestTap,
    this.isRestActive = false,
    this.restRemainingSeconds = 0,
    this.totalRestSeconds = 0,
    this.isRestPaused = false,
    this.onPauseRestTap,
    this.isWorkActive = false,
    this.workRemainingSeconds = 0,
    this.totalWorkSeconds = 0,
    this.isInlineTimedOpen = false,
    this.onTimedChipTap,
  });

  final int index;
  final WorkoutRoutineExercise exercise;
  final ExerciseEntry? exerciseInfo;
  final bool isCurrent;
  final bool isDone;
  final VoidCallback onTap;
  final double? enteredWeightKg;
  final ValueChanged<double?>? onWeightChanged;
  final VoidCallback? onRestTap;
  final bool isRestActive;
  final int restRemainingSeconds;
  final int totalRestSeconds;
  final bool isRestPaused;
  final VoidCallback? onPauseRestTap;
  final bool isWorkActive;
  final int workRemainingSeconds;
  final int totalWorkSeconds;
  final bool isInlineTimedOpen;
  final VoidCallback? onTimedChipTap;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();

  static String _repsLabel(WorkoutRoutineExercise ex) {
    if (ex.mode == WorkoutExerciseMode.timed) {
      final sets = ex.sets ?? 1;
      final dur = _formatDuration(ex.durationSeconds);
      return sets > 1 ? '$sets series · $dur' : dur;
    }
    final sets = ex.sets ?? 4;
    final reps = ex.reps ?? 12;
    return '$sets series · $reps reps';
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return '${m}min';
    return '${m}m ${s}s';
  }
}

class _ExerciseCardState extends State<_ExerciseCard> {
  late final TextEditingController _weightCtrl;
  final FocusNode _weightFocus = FocusNode();
  bool _editingWeight = false;

  @override
  void initState() {
    super.initState();
    final w = widget.enteredWeightKg ?? widget.exercise.weightKg;
    _weightCtrl = TextEditingController(
      text: w == null
          ? ''
          : (w == w.truncateToDouble()
                ? w.toInt().toString()
                : w.toStringAsFixed(1)),
    );
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus && _editingWeight) {
        _commitWeight(_weightCtrl.text);
        setState(() => _editingWeight = false);
      }
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  void _commitWeight(String raw) {
    final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
    setState(() {
      if (parsed != null && parsed > 0) {
        _weightCtrl.text = parsed == parsed.truncateToDouble()
            ? parsed.toInt().toString()
            : parsed.toStringAsFixed(1);
      } else {
        _weightCtrl.text = '';
      }
    });
    widget.onWeightChanged?.call(parsed);
  }

  // Inline weight editing is handled directly in the card via _editingWeight,
  // so the modal sheet implementation was removed to avoid opening a separate
  // overlay. The TextField commits on submit or on focus lost.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showWeight = widget.exercise.showWeightField || widget.exercise.weightKg != null;
    final isTimed = widget.exercise.mode == WorkoutExerciseMode.timed;
    final showRestChip =
        widget.exercise.mode == WorkoutExerciseMode.reps &&
        widget.exercise.restSeconds > 0;
    // Para ejercicios por tiempo: chip siempre visible
    final showTimedChip = isTimed;

    // Tiempo que muestra el chip timed (work restante o total)
    final timedChipSeconds = widget.isWorkActive
        ? widget.workRemainingSeconds
        : widget.isRestActive
            ? widget.restRemainingSeconds
            : widget.exercise.durationSeconds;
    final timedChipIsWork = !widget.isRestActive;

    return Column(
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ExerciseThumb(item: widget.exerciseInfo),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EJERCICIO ${widget.index + 1}',
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.exercise.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _ExerciseCard._repsLabel(widget.exercise),
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 12,
                            ),
                          ),
                          if (showWeight) ...[
                            const SizedBox(width: 6),
                            const Text(
                              '·',
                              style: TextStyle(
                                color: Color(0xFF555555),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (widget.exercise.weightKg != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFD4A853)
                                        .withValues(alpha: isDark ? 0.35 : 0.22),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  () {
                                    final v = widget.exercise.weightKg!;
                                    return v == v.truncateToDouble()
                                        ? '${v.toInt()} kg'
                                        : '${v.toStringAsFixed(1)} kg';
                                  }(),
                                  style: TextStyle(
                                    color: const Color(0xFFD4A853),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              _editingWeight
                                  ? SizedBox(
                                      width: 86,
                                      child: TextField(
                                        controller: _weightCtrl,
                                        focusNode: _weightFocus,
                                        autofocus: true,
                                        textAlign: TextAlign.center,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: theme.dividerColor),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
                                          ),
                                          suffixText: 'kg',
                                        ),
                                        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
                                        onSubmitted: (v) {
                                          _commitWeight(v);
                                          setState(() => _editingWeight = false);
                                          FocusScope.of(context).unfocus();
                                        },
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () {
                                        setState(() => _editingWeight = true);
                                        // request focus on next frame
                                        Future.delayed(Duration.zero, () => _weightFocus.requestFocus());
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : theme.colorScheme.surface,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _weightCtrl.text.isEmpty
                                                ? theme.dividerColor
                                                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          _weightCtrl.text.isEmpty
                                              ? '— kg'
                                              : '${_weightCtrl.text} kg',
                                          style: TextStyle(
                                            color: _weightCtrl.text.isEmpty
                                                ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                                                : theme.colorScheme.onSurface,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showRestChip) const SizedBox(width: 12),
                if (showRestChip)
                  _ExerciseTimerChip(
                    seconds: widget.exercise.restSeconds,
                    isWork: false,
                    canTap: widget.onRestTap != null,
                    onTap: widget.onRestTap,
                  ),
                if (showTimedChip && !showRestChip) const SizedBox(width: 12),
                if (showTimedChip && !showRestChip)
                  _ExerciseTimerChip(
                    seconds: timedChipSeconds,
                    isWork: timedChipIsWork,
                    canTap: widget.onTimedChipTap != null,
                    onTap: widget.onTimedChipTap,
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: (widget.isRestActive && isTimed)
              ? _InlineDualTimer(
                  workRemainingSeconds: 0,
                  totalWorkSeconds: widget.totalWorkSeconds,
                  restRemainingSeconds: widget.restRemainingSeconds,
                  totalRestSeconds: widget.totalRestSeconds,
                  isRestPhase: true,
                  isPaused: widget.isRestPaused,
                  onPauseTap: widget.onPauseRestTap,
                )
              : widget.isRestActive
              ? _InlineRestTimer(
                  remainingSeconds: widget.restRemainingSeconds,
                  totalSeconds: widget.totalRestSeconds,
                  isPaused: widget.isRestPaused,
                  onPauseTap: widget.onPauseRestTap,
                )
              : widget.isInlineTimedOpen
              ? _InlineDualTimer(
                  workRemainingSeconds: widget.workRemainingSeconds,
                  totalWorkSeconds: widget.totalWorkSeconds,
                  restRemainingSeconds: widget.exercise.restSeconds,
                  totalRestSeconds: widget.exercise.restSeconds,
                  isRestPhase: false,
                  isPaused: widget.isRestPaused,
                  onPauseTap: widget.onPauseRestTap,
                )
              : const SizedBox.shrink(),
        ),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }
}


class _ExerciseTimerChip extends StatelessWidget {
  const _ExerciseTimerChip({
    required this.seconds,
    required this.isWork,
    required this.canTap,
    required this.onTap,
  });

  final int seconds;
  final bool isWork; // true = fase work, false = fase rest
  final bool canTap;
  final VoidCallback? onTap;

  String _fmt(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    return rem == 0 ? '${m}min' : '${m}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = canTap
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final textColor = canTap
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 16,
              color: iconColor,
            ),
            const SizedBox(height: 2),
            Text(
              _fmt(seconds),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (isWork)
              Text(
                'W',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _InlineRestTimer extends StatelessWidget {
  const _InlineRestTimer({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isPaused,
    this.onPauseTap,
  });

  final int remainingSeconds;
  final int totalSeconds;
  final bool isPaused;
  final VoidCallback? onPauseTap;

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds > 0
        ? (remainingSeconds / totalSeconds).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      color: Theme.of(context).cardColor,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                        child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 5,
                    backgroundColor: Theme.of(context).dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF22C55E),
                    ),
                  ),
                ),
                Text(
                  '${remainingSeconds}s',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onPauseTap,
            child: Text(
              isPaused ? 'Reanudar' : 'Pausar',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDualTimer extends StatelessWidget {
  const _InlineDualTimer({
    required this.workRemainingSeconds,
    required this.totalWorkSeconds,
    required this.restRemainingSeconds,
    required this.totalRestSeconds,
    required this.isRestPhase,
    required this.isPaused,
    this.onPauseTap,
  });

  final int workRemainingSeconds;
  final int totalWorkSeconds;
  final int restRemainingSeconds;
  final int totalRestSeconds;
  /// true = descanso corriendo (trabajo completado), false = trabajo corriendo
  final bool isRestPhase;
  final bool isPaused;
  final VoidCallback? onPauseTap;

  String _fmt(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    return rem == 0 ? '${m}min' : '${m}m ${rem}s';
  }

  @override
  Widget build(BuildContext context) {
    // --- Lado izquierdo: Trabajo (azul) ---
    final workProgress = isRestPhase
        ? 0.0
        : totalWorkSeconds > 0
            ? (workRemainingSeconds / totalWorkSeconds).clamp(0.0, 1.0)
            : 0.0;
    final workText = isRestPhase ? '\u2713' : _fmt(workRemainingSeconds);
    const workColor = Color(0xFF3B82F6); // azul

    // --- Lado derecho: Descanso (verde) ---
    final restProgress = isRestPhase
        ? (totalRestSeconds > 0
            ? (restRemainingSeconds / totalRestSeconds).clamp(0.0, 1.0)
            : 0.0)
        : 1.0;
    final restText = _fmt(isRestPhase ? restRemainingSeconds : totalRestSeconds);
    const restColor = Color(0xFF22C55E); // verde
    final restLabelColor = isRestPhase ? restColor : const Color(0xFF888888);
    final restTextColor = isRestPhase
      ? Theme.of(context).colorScheme.onSurface
      : const Color(0xFF888888);

    return Container(
      color: Theme.of(context).cardColor,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // LEFT: trabajo
              Column(
                children: [
                  Text(
                    'Trabajo',
                    style: TextStyle(
                      color: isRestPhase
                          ? workColor.withValues(alpha: 0.5)
                          : workColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: workProgress,
                            strokeWidth: 5,
                            backgroundColor: const Color(0xFF2A2A2A),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isRestPhase
                                  ? workColor.withValues(alpha: 0.3)
                                  : workColor,
                            ),
                          ),
                        ),
                        Text(
                          workText,
                          style: TextStyle(
                            color: isRestPhase
                                ? workColor.withValues(alpha: 0.5)
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: isRestPhase ? 26 : 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Divider vertical
              Container(
                width: 1,
                height: 80,
                color: Theme.of(context).dividerColor,
              ),
              // RIGHT: descanso
              Column(
                children: [
                  Text(
                    'Descanso',
                    style: TextStyle(
                      color: restLabelColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: restProgress,
                            strokeWidth: 5,
                            backgroundColor: const Color(0xFF2A2A2A),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isRestPhase
                                  ? restColor
                                  : const Color(0xFF3A3A3A),
                            ),
                          ),
                        ),
                        Text(
                          restText,
                          style: TextStyle(
                            color: restTextColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onPauseTap,
            child: Text(
              isPaused ? 'Reanudar' : 'Pausar',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseThumb extends StatelessWidget {
  const _ExerciseThumb({required this.item});

  final ExerciseEntry? item;

  @override
  Widget build(BuildContext context) {
    final imageBytes = item?.imageBytes;
    final imageUrl = item?.imageUrl ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 70,
        height: 70,
        color: Theme.of(context).colorScheme.surface,
        child: imageBytes != null
            ? Image.memory(imageBytes, fit: BoxFit.cover)
            : imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _ImgPlaceholder(),
              )
            : const _ImgPlaceholder(),
      ),
    );
  }
}

class _TimerBottomSheet extends StatelessWidget {
  const _TimerBottomSheet({
    required this.currentExerciseName,
    required this.currentIndex,
    required this.totalExercises,
    required this.currentSet,
    required this.totalSets,
    required this.currentRound,
    required this.totalRounds,
    required this.primaryLabel,
    required this.primarySeconds,
    required this.primaryBackground,
    required this.primaryTextColor,
    required this.secondaryLabel,
    required this.secondarySeconds,
    required this.secondaryBackground,
    required this.secondaryTextColor,
    required this.phaseKey,
    required this.isPaused,
    required this.isRepMode,
    required this.isRestOnly,
    required this.onPauseResume,
    required this.onMinimizePanel,
    required this.onClose,
    required this.onCompleteRepExercise,
  });

  final String currentExerciseName;
  final int currentIndex;
  final int totalExercises;
  final int currentSet;
  final int totalSets;
  final int currentRound;
  final int totalRounds;
  final String primaryLabel;
  final int primarySeconds;
  final Color primaryBackground;
  final Color primaryTextColor;
  final String secondaryLabel;
  final int secondarySeconds;
  final Color secondaryBackground;
  final Color secondaryTextColor;
  final _SessionPhase phaseKey;
  final bool isPaused;
  final bool isRepMode;
  final bool isRestOnly;
  final VoidCallback onPauseResume;
  final VoidCallback onMinimizePanel;
  final VoidCallback onClose;
  final VoidCallback onCompleteRepExercise;

  String get _setLabel {
    if (totalSets <= 1) return '';
    return '  �  Serie ${currentSet + 1}/$totalSets';
  }

  String get _roundLabel {
    if (totalRounds <= 1) return '';
    return 'R${currentRound + 1}/$totalRounds  �  ';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 242,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: isRestOnly
                  ? _AnimatedPhasePanel(
                      label: primaryLabel,
                      background: primaryBackground,
                      textColor: primaryTextColor,
                      seconds: primarySeconds,
                      labelSize: 28,
                      timeSize: 164,
                      alignment: Alignment.center,
                    )
                  : isRepMode
                  ? _RepModePanel(
                      restLabel: secondaryLabel,
                      restSeconds: secondarySeconds,
                      restBackground: secondaryBackground,
                      restTextColor: secondaryTextColor,
                      onDone: onCompleteRepExercise,
                    )
                  : _SplitPhaseTimer(
                      primaryLabel: primaryLabel,
                      primarySeconds: primarySeconds,
                      primaryBackground: primaryBackground,
                      primaryTextColor: primaryTextColor,
                      secondaryLabel: secondaryLabel,
                      secondarySeconds: secondarySeconds,
                      secondaryBackground: secondaryBackground,
                      secondaryTextColor: secondaryTextColor,
                      phaseKey: phaseKey,
                    ),
            ),
          ),
          Positioned(
            top: 6,
            left: 12,
            right: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    currentExerciseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (isRepMode || isRestOnly)
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44),
                  child: Text(
                    '$_roundLabel${currentIndex + 1}/$totalExercises$_setLabel',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: (isRepMode || isRestOnly)
                          ? Colors.white70
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x28000000),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  const Spacer(),
                  IconButton(
                    onPressed: onPauseResume,
                    tooltip: isPaused ? 'Reanudar' : 'Pausar',
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  IconButton(
                    onPressed: onMinimizePanel,
                    tooltip: 'Minimizar',
                    icon: const Icon(Icons.minimize_rounded),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String mmss(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

// Panel exclusivo para ejercicios por repeticiones.
// Muestra �nicamente la zona roja (descanso) como bot�n grande.
// Al pulsar se completa la serie/ejercicio y empieza el descanso.
class _RepModePanel extends StatelessWidget {
  const _RepModePanel({
    required this.restLabel,
    required this.restSeconds,
    required this.restBackground,
    required this.restTextColor,
    required this.onDone,
  });

  final String restLabel;
  final int restSeconds;
  final Color restBackground;
  final Color restTextColor;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDone,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: restBackground,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 42,
              color: restTextColor.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 10),
            Text(
              'TERMIN� LAS REPS',
              style: TextStyle(
                color: restTextColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Toca para iniciar descanso (${_TimerBottomSheet.mmss(restSeconds)})',
              style: TextStyle(
                color: restTextColor.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitPhaseTimer extends StatelessWidget {
  const _SplitPhaseTimer({
    required this.primaryLabel,
    required this.primarySeconds,
    required this.primaryBackground,
    required this.primaryTextColor,
    required this.secondaryLabel,
    required this.secondarySeconds,
    required this.secondaryBackground,
    required this.secondaryTextColor,
    required this.phaseKey,
  });

  final String primaryLabel;
  final int primarySeconds;
  final Color primaryBackground;
  final Color primaryTextColor;
  final String secondaryLabel;
  final int secondarySeconds;
  final Color secondaryBackground;
  final Color secondaryTextColor;
  final _SessionPhase phaseKey;

  @override
  Widget build(BuildContext context) {
    final currentKey = 'phase-${phaseKey.name}';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final valueKey = child.key;
        final isIncoming =
            valueKey is ValueKey<String> && valueKey.value == currentKey;
        final slideTween = isIncoming
            ? Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            : Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1));

        return ClipRect(
          child: SlideTransition(
            position: animation
                .drive(CurveTween(curve: Curves.easeInOutCubic))
                .drive(slideTween),
            child: child,
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            ...[currentChild].whereType<Widget>(),
          ],
        );
      },
      child: Column(
        key: ValueKey<String>(currentKey),
        children: [
          Expanded(
            flex: 3,
            child: _AnimatedPhasePanel(
              label: primaryLabel,
              background: primaryBackground,
              textColor: primaryTextColor,
              seconds: primarySeconds,
              labelSize: 28,
              timeSize: 164,
              alignment: Alignment.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: _AnimatedPhasePanel(
              label: secondaryLabel,
              background: secondaryBackground,
              textColor: secondaryTextColor,
              seconds: secondarySeconds,
              labelSize: 18,
              timeSize: 74,
              alignment: Alignment.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPhasePanel extends StatelessWidget {
  const _AnimatedPhasePanel({
    required this.label,
    required this.background,
    required this.textColor,
    required this.seconds,
    required this.labelSize,
    required this.timeSize,
    required this.alignment,
  });

  final String label;
  final Color background;
  final Color textColor;
  final int seconds;
  final double labelSize;
  final double timeSize;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: background,
      alignment: alignment,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 95;
          final compactLabelSize = isCompact ? (labelSize * 0.72) : labelSize;
          final compactTimeSize = isCompact ? (timeSize * 0.62) : timeSize;
          final compactGap = isCompact ? 2.0 : 8.0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: compactLabelSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      height: 1,
                    ),
                  ),
                  SizedBox(height: compactGap),
                  Text(
                    _TimerBottomSheet.mmss(seconds),
                    style: TextStyle(
                      color: textColor,
                      fontSize: compactTimeSize,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TimerBubble extends StatelessWidget {
  const _TimerBubble({
    required this.topLabel,
    required this.topSeconds,
    required this.topBackground,
    required this.topTextColor,
    required this.bottomLabel,
    required this.bottomSeconds,
    required this.bottomBackground,
    required this.bottomTextColor,
    this.isRestOnly = false,
    required this.onTap,
  });

  final String topLabel;
  final int topSeconds;
  final Color topBackground;
  final Color topTextColor;
  final String bottomLabel;
  final int bottomSeconds;
  final Color bottomBackground;
  final Color bottomTextColor;
  final bool isRestOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 132,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: isRestOnly
            ? Container(
                width: double.infinity,
                color: topBackground,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      topLabel,
                      style: TextStyle(
                        color: topTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _TimerBottomSheet.mmss(topSeconds),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: topTextColor,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: double.infinity,
                      color: topBackground,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            topLabel,
                            style: TextStyle(
                              color: topTextColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _TimerBottomSheet.mmss(topSeconds),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: topTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      color: bottomBackground,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            bottomLabel,
                            style: TextStyle(
                              color: bottomTextColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _TimerBottomSheet.mmss(bottomSeconds),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: bottomTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.totalSeconds, required this.onFinish});

  final int totalSeconds;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F8F5A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Entrenamiento completado',
            style: TextStyle(
              color: Color(0xFF9AE6B4),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Tiempo total: ${_TimerBottomSheet.mmss(totalSeconds)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Finalizar y valorar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyFinishButton extends StatelessWidget {
  const _StickyFinishButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: AppTheme.pageBackgroundFor(context),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              '✅  Finalizar entreno',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.fitness_center_outlined,
        color: Color(0xFF444466),
        size: 24,
      ),
    );
  }
}

class _TrainingExerciseDetailSheet extends StatelessWidget {
  const _TrainingExerciseDetailSheet({required this.item});

  final ExerciseEntry item;

  Widget _buildExerciseImage() {
    if (item.imageBytes != null) {
      return Image.memory(
        item.imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (item.imageUrl.isNotEmpty) {
      return Image.network(
        item.imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Text(
            'Sin imagen disponible',
            style: TextStyle(color: Color(0xFF7F7F7F), fontSize: 13),
          ),
        ),
      );
    }

    return const Center(
      child: Text(
        'Sin imagen disponible',
        style: TextStyle(color: Color(0xFF7F7F7F), fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muscles = item.muscles.isEmpty
        ? <String>['No especificado']
        : item.muscles;
    final equipment = item.equipment.isEmpty
        ? <String>['No especificado']
        : item.equipment;

    return DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.modalSurfaceFor(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: AppTheme.modalShadowFor(context),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          splashRadius: 18,
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 190,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildExerciseImage(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B1F12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.category.isEmpty ? 'General' : item.category,
                            style: const TextStyle(
                              color: Color(0xFFE67E22),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D2A3A),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.level.isEmpty ? 'Sin nivel' : item.level,
                            style: const TextStyle(
                              color: Color(0xFF67B3FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _TrainingModalBlock(
                      icon: '?',
                      title: 'Descripcion',
                      child: Text(
                        item.description.isEmpty
                            ? 'Sin descripcion disponible.'
                            : item.description,
                        style: const TextStyle(
                          color: Color(0xFFCFCFCF),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    _TrainingModalBlock(
                      icon: '?',
                      title: 'Musculos trabajados',
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: muscles
                            .map(
                              (muscle) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1D2A3A),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  muscle,
                                  style: const TextStyle(
                                    color: Color(0xFF67B3FF),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    _TrainingModalBlock(
                      icon: '??',
                      title: 'Equipamiento',
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: equipment
                            .map(
                              (tool) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2F2F2F),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tool,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    _TrainingModalBlock(
                      icon: '?',
                      title: 'Consejos de ejecucion',
                      highlighted: true,
                      child: Text(
                        item.tips.isEmpty
                            ? 'Sin consejos registrados.'
                            : item.tips,
                        style: const TextStyle(
                          color: Color(0xFFE67E22),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).cardColor,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Cerrar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrainingModalBlock extends StatelessWidget {
  const _TrainingModalBlock({
    required this.icon,
    required this.title,
    required this.child,
    this.highlighted = false,
  });

  final String icon;
  final String title;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                icon,
                style: const TextStyle(color: Color(0xFFE67E22), fontSize: 14),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SessionFeedbackResult {
  const _SessionFeedbackResult({required this.rating, required this.comment});

  final int rating;
  final String comment;
}

class _SessionFeedbackSheet extends StatefulWidget {
  const _SessionFeedbackSheet();

  @override
  State<_SessionFeedbackSheet> createState() => _SessionFeedbackSheetState();
}

class _SessionFeedbackSheetState extends State<_SessionFeedbackSheet> {
  int _rating = 5;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.2),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottom),
            decoration: BoxDecoration(
              color: const Color(0xCC0D0D0D),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.8,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD166),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'VALORA TU ENTRENAMIENTO',
                        style: TextStyle(
                          color: const Color(0xFFFFD166),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      return GestureDetector(
                        onTap: () => setState(() => _rating = star),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            star <= _rating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: star <= _rating
                                ? const Color(0xFFFFD166)
                                : Colors.white.withValues(alpha: 0.25),
                            size: 42,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),
                  // Separator
                  Container(
                    width: double.infinity,
                    height: 0.8,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 16),
                  // Sugerencia label
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sugerencia (opcional)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Textarea
                  TextField(
                    controller: _commentCtrl,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe una sugerencia para mejorar la rutina...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.28),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFFFD166),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _SessionFeedbackResult(
                            rating: _rating,
                            comment: _commentCtrl.text,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Guardar y salir',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
