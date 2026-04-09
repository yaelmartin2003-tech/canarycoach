import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/exercise_store.dart';
import '../../data/user_store.dart';
import '../../theme/app_theme.dart';
import '../../app.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({
    super.key,
    this.onViewTracking,
    this.onViewEvolution,
  });

  final void Function(BuildContext)? onViewTracking;
  final void Function(BuildContext)? onViewEvolution;

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

List<({String name, double delta})> _buildImprovements(
  List<ExerciseWeightLogEntry> allLogs,
) {
  final grouped = <String, List<ExerciseWeightLogEntry>>{};
  for (final log in allLogs) {
    grouped.putIfAbsent(log.exerciseName, () => []).add(log);
  }
  final improvements = <({String name, double delta})>[];
  for (final entry in grouped.entries) {
    final logs = [...entry.value]..sort((a, b) => a.date.compareTo(b.date));
    if (logs.length >= 2 && logs.last.weightKg > logs.first.weightKg) {
      improvements.add((
        name: entry.key,
        delta: logs.last.weightKg - logs.first.weightKg,
      ));
    }
  }
  return improvements;
}

int _calcWeeklyStreak(
  List<ScheduledRoutineAssignment> scheduled,
  List<WorkoutCompletion> completed,
) {
  if (scheduled.isEmpty) return 0;

  final completedDates = <DateTime, Set<String>>{};
  for (final c in completed) {
    completedDates.putIfAbsent(c.normalizedDate, () => {}).add(c.routineName);
  }

  // Agrupar asignaciones por semana (lunes)
  final byWeek = <DateTime, List<ScheduledRoutineAssignment>>{};
  for (final s in scheduled) {
    final d = s.normalizedDate;
    final monday = d.subtract(Duration(days: d.weekday - 1));
    byWeek.putIfAbsent(monday, () => []).add(s);
  }

  final sortedWeeks = byWeek.keys.toList()..sort();
  final today = DateTime.now();
  final todayNorm = DateTime(today.year, today.month, today.day);
  final thisMonday = todayNorm.subtract(Duration(days: todayNorm.weekday - 1));

  int streak = 0;
  for (int i = sortedWeeks.length - 1; i >= 0; i--) {
    final weekStart = sortedWeeks[i];
    // Ignorar semana actual en curso
    if (weekStart == thisMonday) continue;
    final weekEnd = weekStart.add(const Duration(days: 6));
    if (weekEnd.isAfter(todayNorm)) continue;

    final assignments = byWeek[weekStart]!;
    final allDone = assignments.every((a) {
      final done = completedDates[a.normalizedDate];
      return done != null && done.contains(a.routineName);
    });

    if (allDone) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}

class _ProgressTabState extends State<ProgressTab> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precargar logos/recursos usados en la app para evitar saltos al volver
    precacheImage(const AssetImage('assets/LOGO APP.png'), context);
    precacheImage(const AssetImage('assets/logo.png'), context);
    precacheImage(const AssetImage('assets/logo sin fondo CanaryCoach.png'), context);
  }
  @override
  Widget build(BuildContext context) {
    final prefs = appThemePrefsNotifier.value;
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final primary = prefs.accent.color;
        final cardTitleStyle = TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.8),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.05,
        );
        final now = DateTime.now();
        final user = UserStore.instance.currentUser;

        final allLogs = user.exerciseWeightLogs;
        final improvements = _buildImprovements(allLogs);
        final dayIndex = now.difference(DateTime(2024, 1, 1)).inDays;
        final List<({String name, double delta})> shownImprovements;
        if (improvements.isEmpty) {
          shownImprovements = [];
        } else {
          final start = (dayIndex * 2) % improvements.length;
          final end = math.min(start + 2, improvements.length);
          shownImprovements = improvements.sublist(start, end);
          if (shownImprovements.length < 2 && improvements.length >= 2) {
            shownImprovements.addAll(
              improvements.sublist(0, 2 - shownImprovements.length),
            );
          }
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Progresos',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 20,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.light
                          ? Colors.white
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // --- Tarjeta ESTE MES ---
              Builder(
                builder: (context) {
                  final now = DateTime.now();
                  final workouts = UserStore.instance.currentUser.completedWorkouts;
                  final diasEsteMes = workouts
                      .where((w) => w.date.year == now.year && w.date.month == now.month)
                      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
                      .toSet()
                      .length;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                            color: AppTheme.modalSurfaceFor(context),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.surfaceShadowFor(
                              context,
                              alpha: 0.12,
                              blurRadius: 20,
                              offsetY: 6,
                              addTopHighlight: true,
                            ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.calendar_month_rounded,
                                  color: const Color(0xFF2ECC71),
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ESTE MES', style: cardTitleStyle),
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '$diasEsteMes',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'días',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface.withOpacity(0.85),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    diasEsteMes == 0
                                        ? 'Aún no has entrenado este mes.'
                                        : 'Has entrenado $diasEsteMes días este mes.',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // --- Tarjeta MEJORAS DESTACADAS ---
              Builder(
                builder: (context) {
                  if (shownImprovements.isEmpty) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                              color: AppTheme.modalSurfaceFor(context),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.surfaceShadowFor(
                                context,
                                alpha: 0.12,
                                blurRadius: 20,
                                offsetY: 6,
                                addTopHighlight: true,
                              ),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.emoji_events_rounded,
                                    color: primary,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEJORAS DESTACADAS', style: cardTitleStyle),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Próximamente: seguimiento de la mejora de tus ejercicios.',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                            color: AppTheme.modalSurfaceFor(context),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.surfaceShadowFor(
                              context,
                              alpha: 0.12,
                              blurRadius: 20,
                              offsetY: 6,
                              addTopHighlight: true,
                            ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.emoji_events_rounded,
                                    color: primary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('MEJORAS DESTACADAS', style: cardTitleStyle),
                                  const SizedBox(height: 6),
                                  ...shownImprovements.map((e) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              '+${e.delta.toStringAsFixed(0)} kg',
                                              style: TextStyle(
                                                color: primary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'en ${e.name}',
                                                style: TextStyle(
                                                  color: theme.colorScheme.onSurface,
                                                  fontSize: 14,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
              const SizedBox(height: 12),
              if (widget.onViewTracking != null)
                _NavQuickCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'Seguimientos',
                  onTap: () => widget.onViewTracking!(context),
                ),
              const SizedBox(height: 8),
              _NavQuickCard(
                icon: Icons.fitness_center_rounded,
                label: 'Pesos',
                onTap: () {
                  // Capturar en background para usar como fallback al hacer pop
                  captureAndStoreAppSnapshot();
                  Navigator.of(context).push(
                    _InteractiveSlideRoute(
                      child: Scaffold(
                        backgroundColor: AppTheme.pageBackgroundFor(context),
                        body: SafeArea(
                          child: const _WeightsPage(),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (widget.onViewEvolution != null) ...[
                const SizedBox(height: 8),
                _NavQuickCard(
                  icon: Icons.timeline_rounded,
                  label: 'Tests de Evolución',
                  onTap: () => widget.onViewEvolution!(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// --- Stats row: racha + mejoras ---

class _EvolutionStatsRow extends StatelessWidget {
  const _EvolutionStatsRow({
    required this.streak,
    required this.improvements,
  });

  final int streak;
  final List<({String name, double delta})> improvements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.cardColor;
    final border = theme.dividerColor;
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Racha
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    'Racha',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$streak',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 28,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                streak == 1 ? 'semana' : 'semanas',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Mejoras
        Container(
          width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF40311C),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        Icons.trending_up_rounded,
                        color: primary,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mejoras recientes',
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.62),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (improvements.isEmpty)
                  Text(
                    '—',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  )
                else
                  ...improvements.map(
                    (imp) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '+${imp.delta % 1 == 0 ? imp.delta.toInt() : imp.delta} kg  ',
                              style: TextStyle(
                                color: primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: imp.name,
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.75),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
    );
  }
}

class _WeightsList extends StatelessWidget {
  const _WeightsList({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.names,
    required this.grouped,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final List<String> names;
  final Map<String, List<ExerciseWeightLogEntry>> grouped;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: TextField(
            controller: searchCtrl,
            onChanged: onSearchChanged,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Buscar ejercicios...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        if (names.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              'Aun no hay pesos guardados en ejercicios.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          )
        else
          ...names.map((exerciseName) {
            final logs = grouped[exerciseName]!;
            final latest = logs.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey('exercise_$exerciseName'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade800,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.delete_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Eliminar ejercicio'),
                      content: Text(
                        '¿Eliminar todos los registros de "$exerciseName"?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ) ??
                      false;
                },
                onDismissed: (_) {
                  UserStore.instance
                      .removeCurrentUserExerciseWeightLogs(exerciseName);
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        enableDrag: false,
                        backgroundColor: Colors.transparent,
                        builder: (_) => RepaintBoundary(
                          child: _ExerciseWeightDetailSheet(
                            exerciseName: exerciseName,
                            initialLogs: logs,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  exerciseName,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '${logs.length} registros',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${latest.weightKg.toStringAsFixed(latest.weightKg % 1 == 0 ? 0 : 1)} kg',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
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
          }),
      ],
    );
  }
}

class _ExerciseWeightDetailSheet extends StatefulWidget {
  const _ExerciseWeightDetailSheet({
    required this.exerciseName,
    required this.initialLogs,
  });

  final String exerciseName;
  final List<ExerciseWeightLogEntry> initialLogs;

  @override
  State<_ExerciseWeightDetailSheet> createState() =>
      _ExerciseWeightDetailSheetState();
}

class _ExerciseWeightDetailSheetState
    extends State<_ExerciseWeightDetailSheet> {
  final TextEditingController _weightCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  List<ExerciseWeightLogEntry> get _logs {
    final all = UserStore.instance.currentUserExerciseWeightLogs();
    return all
        .where((item) => item.exerciseName == widget.exerciseName)
        .toList();
  }

  void _saveWeight() {
    final parsed = double.tryParse(
      _weightCtrl.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return;
    UserStore.instance.addCurrentUserExerciseWeight(
      exerciseName: widget.exerciseName,
      weightKg: parsed,
      date: DateTime.now(),
    );
    setState(() {
      _weightCtrl.clear();
    });
  }

  String _formatDate(DateTime date) {
    const months = <String>[
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
    return '${date.day} de ${months[date.month - 1]}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    final chartPoints = logs.reversed.take(8).toList();
    final modalColor = AppTheme.modalSurfaceFor(context);
    final modalBorder = AppTheme.modalBorderFor(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10),
      decoration: BoxDecoration(
        color: modalColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: modalBorder),
        boxShadow: AppTheme.modalShadowFor(context),
      ),
      child: Column(
        children: [
          SizedBox(height: 6),
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
                        color: AppColors.secondaryText,
                      ),
                    ),
                    Text(
                      'Volver',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
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
                              color: Color(0xFF40311C),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              Icons.trending_up_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.exerciseName,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '${logs.length} registros',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: SizedBox(
                          height: 190,
                          child: RepaintBoundary(
                            child: _WeightLineChart(points: chartPoints),
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registrar Nuevo Peso',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
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
                                        TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Peso en kg',
                                      hintStyle: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                                      ),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surface,
                                      contentPadding:
                                          EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _saveWeight,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Historial',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...logs.map((item) {
                        final formatted = item.weightKg % 1 == 0
                            ? item.weightKg.toStringAsFixed(0)
                            : item.weightKg.toStringAsFixed(1);
                        return Dismissible(
                          key: ValueKey(
                            'log_${item.exerciseName}_${item.date.millisecondsSinceEpoch}',
                          ),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade800,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Eliminar registro'),
                                content: Text('¿Eliminar el registro de ${formatted} kg del ${_formatDate(item.date)}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            return confirmed ?? false;
                          },
                          onDismissed: (_) {
                            UserStore.instance
                                .removeCurrentUserExerciseWeightEntry(
                              item.exerciseName,
                              item.date,
                            );
                            setState(() {});
                          },
                          child: Container(
                            margin: EdgeInsets.only(bottom: 10),
                            padding: EdgeInsets.all(12),
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
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 16,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _formatDate(item.date),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
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
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Eliminar registro'),
                                        content: Text('¿Eliminar el registro de ${formatted} kg del ${_formatDate(item.date)}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok ?? false) {
                                      UserStore.instance.removeCurrentUserExerciseWeightEntry(
                                        item.exerciseName,
                                        item.date,
                                      );
                                      setState(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  tooltip: 'Eliminar registro',
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

class _WeightLineChart extends StatefulWidget {
  const _WeightLineChart({required this.points});

  final List<ExerciseWeightLogEntry> points;

  @override
  State<_WeightLineChart> createState() => _WeightLineChartState();
}

class _WeightLineChartState extends State<_WeightLineChart> {
  int? _selectedIndex;

  static const double _leftPad = 34.0;
  static const double _rightPad = 10.0;
  static const double _topPad = 12.0;
  static const double _bottomPad = 28.0;

  List<Offset> _computeOffsets(Size size) {
    final chartRect = Rect.fromLTWH(
      _leftPad, _topPad,
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
      final dy = chartRect.bottom - ((pts[i].weightKg - minW) / range) * chartRect.height;
      return Offset(dx, dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const Center(
        child: Text(
          'Sin datos',
          style: TextStyle(color: AppColors.secondaryText),
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
              if (d < minDist) { minDist = d; nearest = i; }
            }
            setState(() {
              _selectedIndex = nearest == _selectedIndex ? null : nearest;
            });
          },
          child: CustomPaint(
            painter: _WeightLineChartPainter(
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

class _WeightLineChartPainter extends CustomPainter {
  _WeightLineChartPainter(this.points, this.selectedIndex, this.accent);

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

    if (selectedIndex != null && selectedIndex! < points.length) {
      final p = pointAt(selectedIndex!);
      canvas.drawCircle(p, 9, Paint()..color = accent.withValues(alpha: 0.25));
      canvas.drawCircle(p, 5.5, Paint()..color = accent);
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);

      final sel = points[selectedIndex!];
      final val = sel.weightKg % 1 == 0
          ? sel.weightKg.toStringAsFixed(0)
          : sel.weightKg.toStringAsFixed(1);
      final d = sel.date;
      final label =
          '$val kg  ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const hPad = 9.0;
      const vPad = 6.0;
      final tw = tp.width + hPad * 2;
      final th = tp.height + vPad * 2;
      var tx = p.dx - tw / 2;
      var ty = p.dy - th - 12;
      tx = tx.clamp(chartRect.left, chartRect.right - tw);
      if (ty < chartRect.top) ty = p.dy + 12;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tw, th), const Radius.circular(7)),
        Paint()..color = const Color(0xFF1E2230),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tw, th), const Radius.circular(7)),
        Paint()
          ..color = accent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      tp.paint(canvas, Offset(tx + hPad, ty + vPad));
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final value = minWeight + ((4 - i) / 4) * range;
      textPainter.text = TextSpan(
        text: value.toStringAsFixed(0),
        style: const TextStyle(color: Color(0xFF8FA0B8), fontSize: 11),
      );
      textPainter.layout();
      final y =
          chartRect.top + (chartRect.height * i / 4) - (textPainter.height / 2);
      textPainter.paint(canvas, Offset(4, y));
    }

    final showIndexes = <int>{0, points.length - 1};
    if (points.length > 2) {
      showIndexes.add(points.length ~/ 2);
    }

    for (final i in showIndexes) {
      final p = pointAt(i);
      final date = points[i].date;
      final label =
          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFF8FA0B8), fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(p.dx - (textPainter.width / 2), chartRect.bottom + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeightLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.accent != accent;
  }
}

class _NavQuickCard extends StatelessWidget {
  const _NavQuickCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final divider = Theme.of(context).dividerColor;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? AppTheme.modalSurfaceFor(context) : surface,
          borderRadius: BorderRadius.circular(14),
          border: isLight ? null : Border.all(color: divider),
          boxShadow: isLight ? AppTheme.surfaceShadowFor(context) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightsPage extends StatefulWidget {
  const _WeightsPage();

  @override
  State<_WeightsPage> createState() => _WeightsPageState();
}

class _WeightsPageState extends State<_WeightsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final logs = UserStore.instance.currentUserExerciseWeightLogs();

        final Map<String, List<ExerciseWeightLogEntry>> grouped = {};
        for (final l in logs) {
          grouped.putIfAbsent(l.exerciseName, () => []).add(l);
        }

        final search = _searchCtrl.text.trim().toLowerCase();
        final names = grouped.keys
            .where((n) => search.isEmpty || n.toLowerCase().contains(search))
            .toList()
          ..sort((a, b) {
            final aDate = grouped[a]!.first.date;
            final bDate = grouped[b]!.first.date;
            return bDate.compareTo(aDate);
          });

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pesos',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openRegisterWeightSheet(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Registrar peso'),
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _WeightsList(
                searchCtrl: _searchCtrl,
                onSearchChanged: (_) => setState(() {}),
                names: names,
                grouped: grouped,
              ),
            ],
          ),
        );
      },
    );
  }

  void _openRegisterWeightSheet(BuildContext pageContext) {
    final exercises = ExerciseStore.instance.exercises;
    String? selectedExercise;
    final weightCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    var filterText = '';

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final bottom = MediaQuery.of(sheetCtx).viewInsets.bottom +
                MediaQuery.viewPaddingOf(sheetCtx).bottom;
            final filtered = exercises
                .where((e) => filterText.isEmpty ||
                    e.name.toLowerCase().contains(filterText.toLowerCase()))
                .toList();

            return RepaintBoundary(child: Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.85,
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(sheetCtx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: AppTheme.modalShadowFor(sheetCtx),
              ),
              padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedExercise == null
                              ? 'Selecciona un ejercicio'
                              : 'Registrar peso',
                          style: TextStyle(
                            color: Theme.of(sheetCtx).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedExercise == null) ...[
                    // Búsqueda de ejercicio
                    TextField(
                      controller: searchCtrl,
                      onChanged: (v) => setSheet(() => filterText = v),
                      style: TextStyle(color: Theme.of(sheetCtx).colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Buscar ejercicio del catálogo...',
                        hintStyle: TextStyle(
                          color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Theme.of(sheetCtx).colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No hay ejercicios en el catálogo',
                                style: TextStyle(
                                  color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final ex = filtered[i];
                                return ListTile(
                                  title: Text(
                                    ex.name,
                                    style: TextStyle(
                                      color: Theme.of(sheetCtx).colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    ex.category,
                                    style: TextStyle(
                                      color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.chevron_right_rounded,
                                    color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.4),
                                  ),
                                  onTap: () => setSheet(() => selectedExercise = ex.name),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    // Pantalla de ingreso de peso
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetCtx).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(sheetCtx).dividerColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.fitness_center_rounded, size: 18, color: AppColors.secondaryText),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedExercise!,
                              style: TextStyle(
                                color: Theme.of(sheetCtx).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setSheet(() => selectedExercise = null),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: Theme.of(sheetCtx).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      style: TextStyle(
                        color: Theme.of(sheetCtx).colorScheme.onSurface,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Peso (kg)',
                        hintText: 'Ej: 80.5',
                        labelStyle: TextStyle(
                          color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        hintStyle: TextStyle(
                          color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        suffixText: 'kg',
                        filled: true,
                        fillColor: Theme.of(sheetCtx).colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(sheetCtx).colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final raw = weightCtrl.text.trim().replaceAll(',', '.');
                          final kg = double.tryParse(raw);
                          if (kg == null || kg <= 0) return;
                          UserStore.instance.addCurrentUserExerciseWeight(
                            exerciseName: selectedExercise!,
                            weightKg: kg,
                          );
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(
                              content: Text('Peso registrado: $selectedExercise — ${kg}kg'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(sheetCtx).colorScheme.primary,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Guardar peso', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ],
              ),
            ));
          },
        );
      },
    );
  }
}

class _InteractiveSlideRoute<T> extends PageRoute<T> {
  _InteractiveSlideRoute({required this.child, this.backgroundSnapshot});

  final Widget child;
  final Uint8List? backgroundSnapshot;

  AnimationController? _internalController;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  AnimationController createAnimationController() {
    assert(navigator != null);
    _internalController = AnimationController(vsync: navigator!.overlay!, duration: transitionDuration);
    return _internalController!;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final _snap = backgroundSnapshot ?? lastAppSnapshot;
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.transparent),
      if (_snap != null)
        Image.memory(
          _snap,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      _LeftEdgeDragDismissible(
        child: child,
        dragAreaFraction: 0.5,
        routeController: _internalController,
      ),
    ]);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (animation.status == AnimationStatus.reverse) return child;
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final offset = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved);
    return SlideTransition(position: offset, child: child);
  }
}

class _LeftEdgeDragDismissible extends StatefulWidget {
  const _LeftEdgeDragDismissible({required this.child, this.dragAreaFraction = 0.5, this.routeController});

  final Widget child;
  final double dragAreaFraction;
  final AnimationController? routeController;

  @override
  State<_LeftEdgeDragDismissible> createState() => _LeftEdgeDragDismissibleState();
}

class _LeftEdgeDragDismissibleState extends State<_LeftEdgeDragDismissible>
    with SingleTickerProviderStateMixin {
  double _offset = 0.0;
  late AnimationController _ctrl;
  late Animation<double> _anim;
  bool _dismissing = false;
  OverlayEntry? _overlayEntry;
  AnimationController? _overlayFadeCtrl;
  AnimationController? _routeController;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    _anim = _ctrl.drive(Tween<double>(begin: 0.0, end: 0.0));
    _ctrl.addListener(() => setState(() {}));
    _ctrl.addStatusListener((s) {
      // Solo ejecutar esta lógica si no hay un controller de ruta disponible
      if (_routeController != null) return;
      if (s == AnimationStatus.completed && _dismissing) {
        if (!mounted) return;
        final modal = ModalRoute.of(context);
        if (modal == null) return;
        if (modal.isCurrent) {
          final overlay = Overlay.of(context);

          if (lastAppSnapshot != null && _overlayEntry == null) {
            _overlayFadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
            _overlayFadeCtrl!.value = 1.0;
            _overlayEntry = OverlayEntry(builder: (ctx) {
              return FadeTransition(
                opacity: _overlayFadeCtrl!,
                child: Positioned.fill(
                  child: Image.memory(
                    lastAppSnapshot!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              );
            });
            overlay?.insert(_overlayEntry!);
          }

          Navigator.of(context).maybePop().then((_) {
            if (_overlayEntry != null && _overlayFadeCtrl != null) {
              _overlayFadeCtrl!.animateTo(0.0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut).then((_) {
                try {
                  _overlayEntry?.remove();
                } catch (_) {}
                _overlayEntry = null;
                _overlayFadeCtrl?.dispose();
                _overlayFadeCtrl = null;
              });
            }
          });
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.routeController != null) {
      _routeController = widget.routeController;
      return;
    }
    try {
      final modal = ModalRoute.of(context);
      if (modal != null) {
        final dyn = modal as dynamic;
        final ctrl = dyn.controller;
        if (ctrl is AnimationController) _routeController = ctrl;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayFadeCtrl?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _handleStart(DragStartDetails d) {
    final maxStart = MediaQuery.of(context).size.width * widget.dragAreaFraction;
    if (d.localPosition.dx > maxStart) return;
    _ctrl.stop();
    _dismissing = false;
  }

  void _handleUpdate(DragUpdateDetails d) {
    final width = MediaQuery.of(context).size.width;
    if (_routeController != null) {
      _offset += d.delta.dx;
      if (_offset < 0) _offset = 0;
      _offset = _offset.clamp(0.0, width);
      final v = (1.0 - (_offset / width)).clamp(0.0, 1.0);
      try {
        _routeController!.value = v;
      } catch (_) {}
      setState(() {});
    } else {
      setState(() {
        _offset += d.delta.dx;
        if (_offset < 0) _offset = 0;
      });
    }
  }

  void _handleEnd(DragEndDetails e) {
    final width = MediaQuery.of(context).size.width;
    final velocity = e.primaryVelocity ?? 0.0;
    final shouldDismiss = _offset > width * 0.25 || velocity > 400;
    if (_routeController != null) {
      if (shouldDismiss) {
        _dismissing = true;
        _routeController!.animateTo(0.0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut).then((_) {
          if (!mounted) return;
          Navigator.of(context).maybePop();
        });
      } else {
        _dismissing = false;
        _routeController!.animateTo(1.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut).then((_) {
          if (!mounted) return;
          setState(() => _offset = 0.0);
        });
      }
    } else {
      if (shouldDismiss) {
        _dismissing = true;
        _anim = Tween<double>(begin: _offset, end: width).animate(
          CurvedAnimation(parent: _ctrl..duration = const Duration(milliseconds: 180), curve: Curves.easeOut),
        );
        _ctrl.forward(from: 0.0);
      } else {
        _dismissing = false;
        _anim = Tween<double>(begin: _offset, end: 0.0).animate(
          CurvedAnimation(parent: _ctrl..duration = const Duration(milliseconds: 200), curve: Curves.easeOut),
        );
        _ctrl.forward(from: 0.0).then((_) {
          setState(() => _offset = 0.0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final effective = _routeController != null
      ? 0.0
      : (_ctrl.isAnimating ? _anim.value : _offset);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_routeController == null)
          Transform.translate(offset: Offset(effective, 0), child: widget.child)
        else
          widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * widget.dragAreaFraction,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _handleStart,
            onHorizontalDragUpdate: _handleUpdate,
            onHorizontalDragEnd: _handleEnd,
          ),
        ),
      ],
    );
  }
}
