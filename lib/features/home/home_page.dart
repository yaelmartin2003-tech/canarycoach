import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/cloudinary_service.dart';
import '../../data/user_store.dart';
import 'progress_tab.dart';
import 'evolution_tab.dart';
// import '../shared/photo_viewer_dialog.dart';
import '../training/training_page.dart';
import '../../theme/app_theme.dart';
import '../../app.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _pageScrollController = ScrollController();
  bool _showLockFlash = false;

  Future<void> _startTrainingForAssignment(
    BuildContext context,
    ScheduledRoutineAssignment assignment,
  ) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrainingPage(
          routineName: assignment.routineName,
          forDate: assignment.date,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _buildGreeting();

    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final theme = Theme.of(context);
        final accent = theme.colorScheme.primary;
        final displayName = UserStore.instance.currentUser.name
            .split(' ')
            .first;
        return SafeArea(
          bottom: false,
          child: ScrollbarTheme(
            data: ScrollbarTheme.of(context).copyWith(
              thumbColor: WidgetStateProperty.all(accent),
              trackColor: WidgetStateProperty.all(theme.dividerColor),
              trackBorderColor: WidgetStateProperty.all(Colors.transparent),
              radius: const Radius.circular(999),
              thickness: WidgetStateProperty.all(6),
            ),
            child: RawScrollbar(
              controller: _pageScrollController,
              thumbVisibility: false,
              trackVisibility: false,
              radius: const Radius.circular(999),
              thickness: 6,
              child: SingleChildScrollView(
                controller: _pageScrollController,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: saludo + nombre + botón pesa
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    greeting.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayName.isEmpty ? 'Tú' : displayName,
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                final role = UserStore.instance.currentUser.role;
                                final isSinclave = role == AppUserRole.sinclave;
                                if (isSinclave) {
                                  // Mostrar flash de candado y bloquear navegación
                                  setState(() => _showLockFlash = true);
                                  Future.delayed(const Duration(milliseconds: 480), () {
                                    if (mounted) setState(() => _showLockFlash = false);
                                  });
                                  return;
                                }
                                _pushPage(
                                  context,
                                  ProgressTab(
                                    onViewTracking: (ctx) => _pushPage(ctx, const _MonthlyTrackingTab()),
                                    onViewEvolution: (ctx) => _pushPage(ctx, const EvolutionTab()),
                                  ),
                                );
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.modalSurfaceFor(context),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                    child: _showLockFlash
                                        ? Icon(
                                            Icons.lock_rounded,
                                            key: const ValueKey('lock'),
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 22,
                                          )
                                        : Icon(
                                            Icons.fitness_center_rounded,
                                            key: const ValueKey('fitness'),
                                            color: Theme.of(context).colorScheme.onSurface,
                                            size: 22,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                      ],
                    ),
                    const SizedBox(height: 18),
                    // Siempre muestra solo entrenamiento
                    Builder(
                      builder: (context) {
                        final now = DateTime.now();
                        final assignments = UserStore.instance
                            .currentUserAssignmentsForDate(now);
                        return _TrainingTab(
                          assignments: assignments,
                          completedDates:
                              UserStore.instance.currentUserCompletedDates(),
                          onStartAssignment: (assignment) =>
                              _startTrainingForAssignment(context, assignment),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 'Buenos días';
    if (hour >= 12 && hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

class _TrainingTab extends StatelessWidget {
  const _TrainingTab({
    required this.assignments,
    required this.completedDates,
    required this.onStartAssignment,
  });

  final List<ScheduledRoutineAssignment> assignments;
  final Set<DateTime> completedDates;
  final ValueChanged<ScheduledRoutineAssignment> onStartAssignment;

  @override
  Widget build(BuildContext context) {
    final sortedAssignments = [...assignments]
      ..sort((left, right) => left.routineName.compareTo(right.routineName));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sortedAssignments.isEmpty)
          Builder(builder: (ctx) {
            final role = UserStore.instance.currentUser.role;
            final isSinclave = role == AppUserRole.sinclave;
            return _GlassCard(
              child: Text(
                isSinclave
                    ? 'Hasta no obtener una clave de un entrenador no se podran asignar rutinas'
                    : 'Hoy no tienes rutinas asignadas. Cuando tu coach te asigne una rutina para hoy, aquí aparecerá el botón Entrenar.',
                style: const TextStyle(color: AppColors.secondaryText, height: 1.45),
              ),
            );
          })
        else
          Column(
            children: sortedAssignments.map((assignment) {
              final completed = UserStore.instance
                  .isRoutineCompletedForCurrentUserOnDate(
                    assignment.routineName,
                    assignment.date,
                  );
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssignedRoutineCard(
                  routineName: assignment.routineName,
                  completed: completed,
                  onStart: completed
                      ? null
                      : () => onStartAssignment(assignment),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 28),
        _MonthlyCalendar(completedDates: completedDates),
        const SizedBox(height: 20),
        const _DailyMotivation(),
      ],
    );
  }
}

class _AssignedRoutineCard extends StatelessWidget {
  const _AssignedRoutineCard({
    required this.routineName,
    required this.completed,
    required this.onStart,
  });

  final String routineName;
  final bool completed;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final completedColor = const Color(0xFF1F8F5A);

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.surfaceShadowFor(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entrenamiento diario',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routineName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completed ? 'Completada hoy' : 'Asignada para hoy',
                      style: TextStyle(
                        color: completed
                            ? const Color(0xFF86EFAC)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: completed ? completedColor : accent,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  completed ? Icons.check_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(completed ? 'Hecha' : 'Entrenar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyCalendar extends StatelessWidget {
  const _MonthlyCalendar({required this.completedDates});

  final Set<DateTime> completedDates;

  static const List<String> _weekLabels = <String>[
    'L',
    'M',
    'X',
    'J',
    'V',
    'S',
    'D',
  ];
  static const List<String> _monthNames = <String>[
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final offset = (firstDay.weekday + 6) % 7;
    final totalDays = lastDay.day;
    final monthTitle = '${_capitalize(_monthNames[now.month - 1])} ${now.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.surfaceShadowFor(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CALENDARIO',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                monthTitle,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 60), // balance visual
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _weekLabels.length + offset + totalDays,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.96,
            ),
            itemBuilder: (context, index) {
              if (index < _weekLabels.length) {
                return Center(
                  child: Text(
                    _weekLabels[index],
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8F8F8F),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }

              final calendarIndex = index - _weekLabels.length;
              if (calendarIndex < offset) {
                return const SizedBox.shrink();
              }

              final day = calendarIndex - offset + 1;
              final current = DateTime(now.year, now.month, day);
              final isToday = _isSameDate(current, now);
              final isCompleted = completedDates.any(
                (date) => _isSameDate(date, current),
              );

              return DecoratedBox(
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF22C55E) // verde sólido cuando está completado
                      : onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCompleted
                        ? const Color(0xFF22C55E)
                        : isToday
                            ? accent
                            : AppTheme.surfaceBorderFor(context),
                    width: isCompleted ? 0.0 : 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isCompleted
                          ? Colors.white
                          : isToday
                              ? onSurface
                              : onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Entrenado',
                style: TextStyle(color: Color(0xFF8F8F8F), fontSize: 12),
              ),
              const SizedBox(width: 16),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Hoy',
                style: TextStyle(color: Color(0xFF8F8F8F), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String _capitalize(String value) {
    return value.isEmpty
        ? value
        : '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _DailyMotivation extends StatelessWidget {
  const _DailyMotivation();

  static const List<String> _quotes = [
    'El dolor que sientes hoy será la fuerza que sentirás mañana.',
    'No pares cuando estés cansado. Para cuando hayas terminado.',
    'Tu cuerpo puede soportar casi todo. Es tu mente la que debes convencer.',
    'El éxito no es el resultado del esfuerzo espontáneo, sino de la constancia.',
    'Cada rep te acerca más a quien quieres ser.',
    'No se trata de ser el mejor. Se trata de ser mejor que ayer.',
    'La disciplina es elegir entre lo que quieres ahora y lo que más quieres.',
    'Los que dicen que no se puede no deberían interrumpir a los que lo están haciendo.',
    'Hoy entrenas, mañana te lo agradeces.',
    'El único entrenamiento malo es el que no hiciste.',
    'Suda ahora, brilla después.',
    'La constancia vence al talento cuando el talento no es constante.',
    'Cada gran atleta fue una vez un principiante que no se rindió.',
    'Tu límite está en tu cabeza.',
    'Levántate, entrena, sé increíble. Repite.',
    'No busques la facilidad. Busca la fortaleza.',
    'El cuerpo logra lo que la mente cree.',
    'Hoy es el día. No mañana, no el lunes. Hoy.',
    'La motivación te arranca, el hábito te lleva lejos.',
    'Eres más fuerte de lo que piensas.',
    'Cada kilómetro, cada rep, cada serie cuenta.',
    'El desafío de hoy es el calor de mañana.',
    'Entrena duro, recupera bien, repite.',
    'No te compares con nadie, solo con quien eras ayer.',
    'El progreso requiere sacrificio. Tú ya estás aquí.',
    'Persiste. El resultado no se ve de inmediato, pero llega.',
    'El esfuerzo nunca miente.',
    'Convierte tus excusas en energía.',
    'Un día a la vez. Una rep a la vez.',
    'La grandeza no es un destino, es una decisión diaria.',
  ];

  String _quoteForToday() {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return _quotes[dayOfYear % _quotes.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.20);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.40);
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: accent, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    'Frase del día',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _quoteForToday(),
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.90)
                      : Colors.black.withValues(alpha: 0.85),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.borderColor,
  });

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? const Color(0xFF2A2A2A),
          width: borderColor != null ? 1.2 : 0.8,
        ),
      ),
      child: child,
    );
  }
}

void _pushPage(BuildContext ctx, Widget page) {
  // Lanzar captura en background para tener un fallback al hacer pop
  captureAndStoreAppSnapshot();
  Navigator.of(ctx).push(
    _InteractiveSlideRoute(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackgroundFor(ctx),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: page,
          ),
        ),
      ),
    ),
  );
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
    // Avoid running reverse transition when gesture handles animation
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
    // Preferir controller pasado por el widget (desde la ruta interactiva)
    if (widget.routeController != null) {
      _routeController = widget.routeController;
      return;
    }
    // Si no fue pasado, intentar obtener el AnimationController del ModalRoute (si existe)
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
        _offset = _offset.clamp(0.0, width);
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
        // When a route controller is provided, the route's SlideTransition
        // drives the page translation. Avoid applying a second transform
        // to prevent double-translation (which caused the flash).
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

class _MonthlyTrackingTab extends StatefulWidget {
  const _MonthlyTrackingTab();

  @override
  State<_MonthlyTrackingTab> createState() => _MonthlyTrackingTabState();
}

class _MonthlyTrackingTabState extends State<_MonthlyTrackingTab> {
  bool _prefetched = false;

  @override
  void initState() {
    super.initState();
    UserStore.instance.addListener(_onUserStoreChanged);
  }

  void _onUserStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    UserStore.instance.removeListener(_onUserStoreChanged);
    super.dispose();
  }

  Future<void> _openHistoryDetail(
    BuildContext context,
    UserTrackingEntry entry,
    List<UserTrackingEntry> allHistory,
  ) async {
    return Navigator.push<void>(
      context,
      _InteractiveSlideRoute(
        child: _TrackingHistoryDetailSheet(entry: entry, allHistory: allHistory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = UserStore.instance.currentUserTrackingHistory()
      ..sort((a, b) => b.normalizedDate.compareTo(a.normalizedDate));
    final photoHistory = history
        .where((item) => item.photoBytes != null || item.photoUrl.trim().isNotEmpty)
        .toList();

    // Prefetch primeras imágenes de la fila de fotos para hacer la
    // transición y el scroll más suaves (post-frame para no bloquear build).
    if (!_prefetched && photoHistory.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final limit = photoHistory.length < 3 ? photoHistory.length : 3;
        for (int i = 0; i < limit; i++) {
          final item = photoHistory[i];
          if (item.photoUrl.trim().isNotEmpty) {
            try {
              await precacheImage(NetworkImage(item.photoUrl), context);
            } catch (_) {
              // Ignorar errores de precache
            }
          }
        }
      });
      _prefetched = true;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'Seguimiento Mensual',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _openNewTrackingSheet,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nuevo seguimiento'),
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Fotos de progreso ──────────────────────────────────────
          if (photoHistory.isNotEmpty) ...[
            Text(
              'Fotos de progreso',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                cacheExtent: 800,
                itemCount: photoHistory.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = photoHistory[index];
                  final isLatest = index == 0;
                  return InkWell(
                    onTap: () => _openHistoryDetail(context, item, history),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLatest ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                          width: isLatest ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          item.photoBytes != null
                              ? Image.memory(item.photoBytes!, fit: BoxFit.cover)
                              : Image.network(
                                  item.photoUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.image_not_supported_outlined,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                              color: const Color(0x99000000),
                              child: Text(
                                _formatDateShort(item.date),
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Historial ─────────────────────────────────────────────
          if (history.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sin registros aún',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pulsa "Nuevo seguimiento" para empezar',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            ...history.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HistoryItem(
                item: item,
                onTap: () => _openHistoryDetail(context, item, history),
              ),
            )),
        ],
      ),
    );
  }

  void _openNewTrackingSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _NewTrackingSheet(parentContext: context),
    );
  }

  Widget _sheetField(BuildContext ctx, TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 13),
      decoration: _sheetInputDecoration(ctx, hint).copyWith(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  InputDecoration _sheetInputDecoration(BuildContext ctx, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
      filled: true,
      fillColor: Theme.of(ctx).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).dividerColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).dividerColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary)),
    );
  }

}

double? _parseNum(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  return double.tryParse(raw.replaceAll(',', '.'));
}

class _NewTrackingSheet extends StatefulWidget {
  final BuildContext parentContext;
  const _NewTrackingSheet({Key? key, required this.parentContext}) : super(key: key);

  @override
  State<_NewTrackingSheet> createState() => _NewTrackingSheetState();
}

class _NewTrackingSheetState extends State<_NewTrackingSheet> {
  Uint8List? photoBytes;
  String photoUrl = '';
  late TextEditingController weightCtrl;
  late TextEditingController waistCtrl;
  late TextEditingController hipsCtrl;
  late TextEditingController armsCtrl;
  late TextEditingController thighsCtrl;
  late TextEditingController calvesCtrl;
  late TextEditingController notesCtrl;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    weightCtrl = TextEditingController();
    waistCtrl = TextEditingController();
    hipsCtrl = TextEditingController();
    armsCtrl = TextEditingController();
    thighsCtrl = TextEditingController();
    calvesCtrl = TextEditingController();
    notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    weightCtrl.dispose();
    waistCtrl.dispose();
    hipsCtrl.dispose();
    armsCtrl.dispose();
    thighsCtrl.dispose();
    calvesCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Widget _sheetField(BuildContext ctx, TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 13),
      decoration: _sheetInputDecoration(ctx, hint).copyWith(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  InputDecoration _sheetInputDecoration(BuildContext ctx, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
      filled: true,
      fillColor: Theme.of(ctx).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).dividerColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).dividerColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(ctx).colorScheme.primary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.viewPaddingOf(context).bottom;
    return RepaintBoundary(child: Container(
      decoration: BoxDecoration(
        color: AppTheme.modalSurfaceFor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppTheme.modalShadowFor(context),
      ),
      padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nuevo seguimiento',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Fecha
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, size: 16, color: AppColors.secondaryText),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateLong(DateTime.now()),
                    style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Text('Automática', style: TextStyle(color: AppColors.secondaryText, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Foto
            InkWell(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.image, allowMultiple: false, withData: true,
                );
                final bytes = result?.files.single.bytes;
                if (bytes == null || !mounted) return;
                setState(() => photoBytes = bytes);
                final url = await CloudinaryService.uploadImageBytes(
                  bytes, fileName: 'progress_${DateTime.now().millisecondsSinceEpoch}.jpg',
                );
                if (!mounted) return;
                setState(() => photoUrl = url ?? '');
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: photoBytes == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, color: AppColors.secondaryText, size: 28),
                          SizedBox(height: 6),
                          Text('Añadir foto (opcional)', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(photoBytes!, fit: BoxFit.cover),
                          if (photoUrl.isEmpty)
                            const Positioned(
                              bottom: 6, right: 8,
                              child: SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            ),
                          if (photoUrl.isNotEmpty)
                            const Positioned(
                              bottom: 6, right: 8,
                              child: Icon(Icons.cloud_done, color: Colors.greenAccent, size: 18),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            // Medidas
            Text('Medidas (opcional)',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _sheetField(context, weightCtrl, 'Peso (kg)', '70.5')),
              const SizedBox(width: 8),
              Expanded(child: _sheetField(context, waistCtrl, 'Cintura (cm)', '80')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _sheetField(context, hipsCtrl, 'Cadera (cm)', '95')),
              const SizedBox(width: 8),
              Expanded(child: _sheetField(context, armsCtrl, 'Brazos (cm)', '32')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _sheetField(context, thighsCtrl, 'Muslos (cm)', '55')),
              const SizedBox(width: 8),
              Expanded(child: _sheetField(context, calvesCtrl, 'Gemelos (cm)', '35')),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
              decoration: _sheetInputDecoration(context, '¿Cómo te sientes? Notas...'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving || (photoBytes != null && photoUrl.isEmpty)
                    ? null
                    : () {
                        setState(() => isSaving = true);
                        final now = DateTime.now();
                        final entry = UserTrackingEntry(
                          date: DateTime(now.year, now.month, now.day),
                          photoBytes: photoBytes,
                          photoUrl: photoUrl,
                          weightKg: _parseNum(weightCtrl.text),
                          waistCm: _parseNum(waistCtrl.text),
                          hipsCm: _parseNum(hipsCtrl.text),
                          armsCm: _parseNum(armsCtrl.text),
                          thighsCm: _parseNum(thighsCtrl.text),
                          calvesCm: _parseNum(calvesCtrl.text),
                          notes: notesCtrl.text.trim(),
                        );
                        UserStore.instance.addCurrentUserTrackingEntry(entry);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                          const SnackBar(content: Text('Registro guardado correctamente.')),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: isSaving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : photoBytes != null && photoUrl.isEmpty
                        ? const Text('Subiendo foto...')
                        : const Text('Guardar registro',
                            style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.item, required this.onTap});

  final UserTrackingEntry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = item.photoBytes != null || item.photoUrl.trim().isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2D2D2D)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDateLong(item.date),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      hasPhoto
                          ? 'Registro con foto y medidas'
                          : 'Registro de medidas',
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
              SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingHistoryDetailSheet extends StatefulWidget {
  const _TrackingHistoryDetailSheet({
    required this.entry,
    required this.allHistory,
  });

  final UserTrackingEntry entry;
  final List<UserTrackingEntry> allHistory;

  @override
  State<_TrackingHistoryDetailSheet> createState() =>
      _TrackingHistoryDetailSheetState();
}

class _TrackingHistoryDetailSheetState
    extends State<_TrackingHistoryDetailSheet> {
  late UserTrackingEntry _entry;
  late List<UserTrackingEntry> _allHistory;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _allHistory = List.of(widget.allHistory)
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  void _navigateToEntry(UserTrackingEntry e) {
    setState(() => _entry = e);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bool hasPhoto =
        (_entry.photoBytes != null && _entry.photoBytes!.isNotEmpty) ||
        _entry.photoUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBackground,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: Text(
          _formatDateLong(_entry.date),
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ── Foto ──────────────────────────────────────────────
          if (hasPhoto)
            _buildPhoto()
          else
            Container(
              height: 220,
              color: AppColors.card,
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined,
                    color: AppColors.secondaryText, size: 56),
              ),
            ),

          const SizedBox(height: 20),

          // ── Navegación entre entradas ─────────────────────────
          if (_allHistory.length > 1) _buildNavigator(accent),

          const SizedBox(height: 20),

          // ── Medidas ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Medidas',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildMeasurementsGrid(),

          // ── Notas ─────────────────────────────────────────────
          if (_entry.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Notas',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _entry.notes,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    if (_entry.photoBytes != null && _entry.photoBytes!.isNotEmpty) {
      return Image.memory(
        _entry.photoBytes!,
        width: double.infinity,
        height: 320,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      _entry.photoUrl,
      width: double.infinity,
      height: 320,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        height: 220,
        color: AppColors.card,
        child: const Center(
          child: Icon(Icons.broken_image_outlined,
              color: AppColors.secondaryText, size: 56),
        ),
      ),
    );
  }

  Widget _buildNavigator(Color accent) {
    final currentIndex = _allHistory.indexOf(_entry);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex < _allHistory.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavButton(
            icon: Icons.chevron_left,
            label: 'Anterior',
            enabled: hasPrev,
            onTap: hasPrev
                ? () => _navigateToEntry(_allHistory[currentIndex - 1])
                : null,
            accent: accent,
          ),
          Text(
            '${currentIndex + 1} / ${_allHistory.length}',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right,
            label: 'Siguiente',
            enabled: hasNext,
            onTap: hasNext
                ? () => _navigateToEntry(_allHistory[currentIndex + 1])
                : null,
            accent: accent,
            iconRight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsGrid() {
    final items = <_MeasureItem>[
      if (_entry.weightKg != null)
        _MeasureItem(label: 'Peso', value: '${_entry.weightKg} kg',
            icon: Icons.monitor_weight_outlined),
      if (_entry.waistCm != null)
        _MeasureItem(label: 'Cintura', value: '${_entry.waistCm} cm',
            icon: Icons.straighten),
      if (_entry.hipsCm != null)
        _MeasureItem(label: 'Cadera', value: '${_entry.hipsCm} cm',
            icon: Icons.straighten),
      if (_entry.armsCm != null)
        _MeasureItem(label: 'Brazos', value: '${_entry.armsCm} cm',
            icon: Icons.fitness_center),
      if (_entry.forearmCm != null)
        _MeasureItem(label: 'Antebrazos', value: '${_entry.forearmCm} cm',
            icon: Icons.fitness_center),
      if (_entry.chestCm != null)
        _MeasureItem(label: 'Pecho', value: '${_entry.chestCm} cm',
            icon: Icons.straighten),
      if (_entry.thighsCm != null)
        _MeasureItem(label: 'Muslos', value: '${_entry.thighsCm} cm',
            icon: Icons.straighten),
      if (_entry.calvesCm != null)
        _MeasureItem(label: 'Gemelos', value: '${_entry.calvesCm} cm',
            icon: Icons.straighten),
      if (_entry.neckCm != null)
        _MeasureItem(label: 'Cuello', value: '${_entry.neckCm} cm',
            icon: Icons.straighten),
    ];

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Sin medidas registradas.',
          style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (_, i) => _MeasureTile(item: items[i]),
      ),
    );
  }
}

class _MeasureItem {
  const _MeasureItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
}

class _MeasureTile extends StatelessWidget {
  const _MeasureTile({required this.item});
  final _MeasureItem item;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(item.icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
                Text(
                  item.value,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.accent,
    this.onTap,
    this.iconRight = false,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;
  final bool iconRight;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? accent : AppColors.secondaryText;
    final children = [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontSize: 13)),
    ];
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: iconRight ? children.reversed.toList() : children,
      ),
    );
  }
}

String _formatDateShort(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  return '$d ${_monthName(date.month).substring(0, 3)} ${date.year}';
}

String _formatDateLong(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  return '$d de ${_monthName(date.month)}, ${date.year}';
}

String _monthName(int month) {
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
  return months[month - 1];
}