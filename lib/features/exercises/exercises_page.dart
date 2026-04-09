import '../../data/exercise_store.dart';
import '../../data/user_store.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'custom_filter_dropdown.dart';

const Map<String, ({Color bg, Color fg})> _kCategoryChipColors = {
  'Pecho':     (bg: Color(0xFFFFD9D1), fg: Color(0xFF7F1D1D)),
  'Espalda':   (bg: Color(0xFFD6E8FF), fg: Color(0xFF1E3A8A)),
  'Piernas':   (bg: Color(0xFFEDE1FF), fg: Color(0xFF5B21B6)),
  'Hombros':   (bg: Color(0xFFFFE5CF), fg: Color(0xFF9A3412)),
  'Brazos':    (bg: Color(0xFFFFE0EF), fg: Color(0xFF9F1239)),
  'Abdomen':   (bg: Color(0xFFD8F3EE), fg: Color(0xFF115E59)),
  'Cardio':    (bg: Color(0xFFFFD9DC), fg: Color(0xFF991B1B)),
  'Funcional': (bg: Color(0xFFFEF3C7), fg: Color(0xFF854D0E)),
};

class ExercisesPage extends StatefulWidget {
  const ExercisesPage({super.key});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = '';
  String _selectedEquipment = '';
  String _selectedLevel = '';
  int _visibleCount = 20;
  static const int _visibleIncrement = 20;
  bool _wasCurrent = false;
  int _previousVisibleCount = 0;
  final Set<int> _animatedIndices = {}; // índices dentro de la vista visible que ya animaron

  static const List<String> _categories = [
    'Pecho',
    'Espalda',
    'Piernas',
    'Hombros',
    'Brazos',
    'Abdomen',
    'Cardio',
    'Funcional',
  ];

  static const List<String> _equipmentOptions = [
    'Peso corporal',
    'Mancuernas',
    'Barra',
    'Maquina',
    'Polea',
    'Banda elastica',
    'Kettlebell',
    'TRX',
  ];

  static const List<String> _levels = [
    'Principiante',
    'Intermedio',
    'Avanzado',
  ];

  @override
  void initState() {
    super.initState();
    ExerciseStore.instance.addListener(_onStoreChanged);
  }

  void _onStoreChanged() => setState(() {});

  @override
  void dispose() {
    ExerciseStore.instance.removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<ExerciseEntry> get _filteredExercises {
    final query = _searchController.text.trim().toLowerCase();
    return ExerciseStore.instance.exercises.where((exercise) {
      final matchesQuery = query.isEmpty ||
          exercise.name.toLowerCase().contains(query) ||
          exercise.description.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategory.isEmpty || exercise.category == _selectedCategory;
      final matchesEquipment = _selectedEquipment.isEmpty ||
          exercise.equipment.contains(_selectedEquipment);
      final matchesLevel = _selectedLevel.isEmpty || exercise.level == _selectedLevel;
      return matchesQuery && matchesCategory && matchesEquipment && matchesLevel;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedCategory = '';
      _selectedEquipment = '';
      _selectedLevel = '';
    });
  }

  void _openExerciseDetails(ExerciseEntry item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ExerciseDetailSheet(item: item);
      },
    );
  }

  void _animateNewItems(int oldCount, int newCount) {
    if (newCount <= oldCount) return;
    for (int i = oldCount; i < newCount; i++) {
      Future.delayed(Duration(milliseconds: 80 * (i - oldCount)), () {
        if (!mounted) return;
        setState(() {
          _animatedIndices.add(i);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentUser = UserStore.instance.currentUser;
    // Mostrar pantalla bloqueada si:
    // - No hay sesión (id y email vacíos), O
    // - Es usuario normal sin entrenador asignado (fue eliminado o nunca tuvo clave)
    final isBlocked = currentUser.id.isEmpty ||
      currentUser.role == AppUserRole.sinclave ||
      (currentUser.role == AppUserRole.user &&
        (currentUser.trainerId == null || currentUser.trainerId!.trim().isEmpty));
    if (isBlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 64,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 20),
              Text(
                'Acceso restringido',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Necesitas una clave de acceso para ver el catálogo de ejercicios.\nContacta con tu entrenador para obtenerla.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredExercises;
    final visible = filtered.take(_visibleCount).toList();

    // Reset visible count when user returns to this route
    final route = ModalRoute.of(context);
    final isCurrentRoute = route?.isCurrent ?? true;
    if (isCurrentRoute && !_wasCurrent) {
      if (_visibleCount != 20) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _visibleCount = 20;
            _previousVisibleCount = 20;
            _animatedIndices.clear();
          });
        });
      } else {
        // ensure previousVisibleCount matches current visible after navigation
        _previousVisibleCount = _visibleCount;
        _animatedIndices.clear();
      }
      _wasCurrent = true;
    } else if (!isCurrentRoute) {
      _wasCurrent = false;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catalogo de Ejercicios',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? const Color(0xFF111111) : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Encuentra ejercicios por musculo, equipamiento y nivel.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          _FiltersPanel(
            searchController: _searchController,
            categories: _categories,
            equipmentOptions: _equipmentOptions,
            levels: _levels,
            selectedCategory: _selectedCategory,
            selectedEquipment: _selectedEquipment,
            selectedLevel: _selectedLevel,
            onSearchChanged: (_) => setState(() {}),
            onCategoryChanged: (value) {
              setState(() {
                _selectedCategory = value;
              });
            },
            onEquipmentChanged: (value) {
              setState(() {
                _selectedEquipment = value;
              });
            },
            onLevelChanged: (value) {
              setState(() {
                _selectedLevel = value;
              });
            },
            onClearFilters: _clearFilters,
          ),
          SizedBox(height: 18),
          Text(
            '${filtered.length} ejercicios encontrados',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            _EmptyExercisesState(onClearFilters: _clearFilters)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.72,
                      ),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final isPreviouslyVisible = index < _previousVisibleCount;
                        final isAnimated = _animatedIndices.contains(index);

                        if (isAnimated) {
                          return TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOut,
                            builder: (context, t, child) {
                              return Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.95 + 0.05 * t,
                                  child: child,
                                ),
                              );
                            },
                            child: _ExerciseCard(
                              item: item,
                              onTap: () => _openExerciseDetails(item),
                            ),
                          );
                        }

                        // Si es un nuevo slot aún no marcado para animación, lo renderizamos invisible
                        if (!isPreviouslyVisible) {
                          return Opacity(
                            opacity: 0.0,
                            child: _ExerciseCard(
                              item: item,
                              onTap: () => _openExerciseDetails(item),
                            ),
                          );
                        }

                        // Item visible sin animación (items iniciales)
                        return _ExerciseCard(
                          item: item,
                          onTap: () => _openExerciseDetails(item),
                        );
                      },
                    ),
                  );
                },
            ),
          if (filtered.length > visible.length) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                onPressed: () {
                  final total = _filteredExercises.length;
                  final old = _visibleCount;
                  final newCount = (old + _visibleIncrement) > total ? total : (old + _visibleIncrement);
                  _previousVisibleCount = old;
                  setState(() {
                    _visibleCount = newCount;
                  });
                  _animateNewItems(old, newCount);
                },
                child: Text(
                  'Ver más',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

class _FiltersPanel extends StatefulWidget {
  const _FiltersPanel({
    required this.searchController,
    required this.categories,
    required this.equipmentOptions,
    required this.levels,
    required this.selectedCategory,
    required this.selectedEquipment,
    required this.selectedLevel,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onEquipmentChanged,
    required this.onLevelChanged,
    required this.onClearFilters,
  });

  final TextEditingController searchController;
  final List<String> categories;
  final List<String> equipmentOptions;
  final List<String> levels;
  final String selectedCategory;
  final String selectedEquipment;
  final String selectedLevel;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onEquipmentChanged;
  final ValueChanged<String> onLevelChanged;
  final VoidCallback onClearFilters;

  @override
  State<_FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<_FiltersPanel> {
  bool _expanded = false;

  bool get _hasActiveFilters =>
      widget.selectedCategory.isNotEmpty ||
      widget.selectedEquipment.isNotEmpty ||
      widget.selectedLevel.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Chips activos como lista de (label, onRemove)
    final activeChips = <({String label, VoidCallback onRemove})>[
      if (widget.selectedCategory.isNotEmpty)
        (label: widget.selectedCategory, onRemove: () => widget.onCategoryChanged('')),
      if (widget.selectedEquipment.isNotEmpty)
        (label: widget.selectedEquipment, onRemove: () => widget.onEquipmentChanged('')),
      if (widget.selectedLevel.isNotEmpty)
        (label: widget.selectedLevel, onRemove: () => widget.onLevelChanged('')),
    ];

    final cellColor = theme.colorScheme.onSurface.withValues(alpha: 0.06);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chips de filtros activos (visibles siempre que haya filtros seleccionados)
          if (!_expanded && activeChips.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: activeChips.map((chip) {
                final chipBg = isDark ? cellColor : const Color(0xFFF3F4F6);
                final chipText = isDark
                    ? theme.colorScheme.onSurface
                    : const Color(0xFF374151);
                return GestureDetector(
                  onTap: chip.onRemove,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chip.label,
                          style: TextStyle(
                            color: chipText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.close_rounded, size: 13, color: chipText),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          // Fila: buscador + botón expandir filtros
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  onChanged: widget.onSearchChanged,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Buscar ejercicios...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    fillColor: isDark ? cellColor : theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? Colors.transparent : theme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? Colors.transparent : theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _expanded || _hasActiveFilters
                        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
                        : (isDark ? cellColor : const Color(0xFFF3F4F6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: _expanded || _hasActiveFilters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ],
          ),
          // Filtros desplegables
          if (_expanded) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 620;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(
                        child: CustomFilterDropdown(
                          value: widget.selectedCategory,
                          hint: 'Categoria/Musculo',
                          allLabel: 'Todas las categorias',
                          options: widget.categories,
                          onChanged: widget.onCategoryChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomFilterDropdown(
                          value: widget.selectedEquipment,
                          hint: 'Tipo de Equipamiento',
                          allLabel: 'Todos los equipamientos',
                          options: widget.equipmentOptions,
                          onChanged: widget.onEquipmentChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomFilterDropdown(
                          value: widget.selectedLevel,
                          hint: 'Nivel',
                          options: widget.levels,
                          onChanged: widget.onLevelChanged,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    CustomFilterDropdown(
                      value: widget.selectedCategory,
                      hint: 'Categoria/Musculo',
                      allLabel: 'Todas las categorias',
                      options: widget.categories,
                      onChanged: widget.onCategoryChanged,
                    ),
                    const SizedBox(height: 8),
                    CustomFilterDropdown(
                      value: widget.selectedEquipment,
                      hint: 'Tipo de Equipamiento',
                      allLabel: 'Todos los equipamientos',
                      options: widget.equipmentOptions,
                      onChanged: widget.onEquipmentChanged,
                    ),
                    const SizedBox(height: 8),
                    CustomFilterDropdown(
                      value: widget.selectedLevel,
                      hint: 'Nivel',
                      options: widget.levels,
                      onChanged: widget.onLevelChanged,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onClearFilters,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Limpiar filtros'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.allLabel,
  });

  final String value;
  final String hint;
  final String? allLabel;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cellColor = theme.colorScheme.onSurface.withValues(alpha: 0.06);
    final modalColor = AppTheme.modalSurfaceFor(context);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cellColor : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? (allLabel != null ? '' : null) : value,
          isExpanded: true,
          dropdownColor: modalColor,
          hint: Text(
            hint,
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.62)),
          ),
          style: TextStyle(
            color: isDark
                ? theme.colorScheme.onSurface
                : const Color(0xFF374151),
          ),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
          ),
          items: [
            if (allLabel != null)
              DropdownMenuItem<String>(
                value: '',
                child: Text(allLabel!),
              ),
            ...options.map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
            ),
          ],
          onChanged: (value) {
            onChanged(value ?? '');
          },
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.item, required this.onTap});

  final ExerciseEntry item;
  final VoidCallback onTap;

  static Color _dotColor(String level) {
    switch (level) {
      case 'Principiante':
        return const Color(0xFF22C55E);
      case 'Intermedio':
        return const Color(0xFFFACC15);
      default:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final theme = Theme.of(context);
      final isLight = theme.brightness == Brightness.light;
    const lightEdge = Color(0xFFA6ADB5);
    final cat = _kCategoryChipColors[item.category] ??
        (bg: const Color(0xFF2A2A2A), fg: AppColors.secondaryText);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLight
                    ? lightEdge
                    : theme.dividerColor,
                width: isLight ? 1.45 : 1,
              ),
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.11),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.36),
                        blurRadius: 0,
                        spreadRadius: -1,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 110,
                        width: double.infinity,
                        color: theme.colorScheme.surface,
                        child: item.imageBytes != null
                            ? Image.memory(item.imageBytes!, fit: BoxFit.cover)
                            : item.imageUrl.isNotEmpty
                                ? Image.network(
                                    item.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
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
                            color: _dotColor(item.level),
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (item.description.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.description,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                                fontSize: 11,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const Spacer(),
                          _TagChip(
                            label: item.category,
                            backgroundColor: cat.bg,
                            textColor: cat.fg,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                          ),
                          if (item.equipment.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 3,
                              runSpacing: 3,
                              children: item.equipment
                                  .take(2)
                                  .map(
                                    (eq) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isLight
                                              ? lightEdge
                                              : theme.dividerColor,
                                          width: isLight ? 1.15 : 1,
                                        ),
                                        boxShadow: isLight
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.05),
                                                  blurRadius: 5,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Text(
                                        eq,
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface,
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
            ),
          ),
        ),
      );
    } catch (e, s) {
      // Evitar crash por excepción en build y mostrar placeholder
      // Log para diagnosticar
      // ignore: avoid_print
      print('[_ExerciseCard] build error: $e\n$s');
      return Container(
        height: 160,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'Error cargando ejercicio',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
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
        size: 36,
      ),
    );
  }
}

class _ExerciseDetailSheet extends StatelessWidget {
  const _ExerciseDetailSheet({required this.item});

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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final muscles = item.muscles.isEmpty ? <String>['No especificado'] : item.muscles;
    final equipment =
        item.equipment.isEmpty ? <String>['No especificado'] : item.equipment;
    final modalColor = AppTheme.modalSurfaceFor(context);
    final modalBorder = AppTheme.modalBorderFor(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final borderRadius = BorderRadius.vertical(top: Radius.circular(20));
        return Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: modalColor,
            border: isDark ? Border.all(color: modalBorder) : null,
            boxShadow: AppTheme.modalShadowFor(context),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
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
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          splashRadius: 18,
                          icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withValues(alpha: 0.62)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 190,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: isDark ? Border.all(color: theme.dividerColor) : null,
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.09),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: primary.withValues(alpha: isDark ? 0.30 : 0.45),
                            ),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Text(
                            item.category.isEmpty ? 'General' : item.category,
                            style: TextStyle(
                              color: primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1D2A3A)
                                : onSurface.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF2C4761)
                                  : onSurface.withValues(alpha: 0.20),
                            ),
                          ),
                          child: Text(
                            item.level.isEmpty ? 'Sin nivel' : item.level,
                            style: TextStyle(
                              color: isDark ? const Color(0xFF67B3FF) : onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ModalBlock(
                      icon: 'ⓘ',
                      title: 'Descripción',
                      child: Text(
                        item.description.isEmpty
                            ? 'Sin descripción disponible.'
                            : item.description,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFCFCFCF)
                              : const Color(0xFF374151),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    _ModalBlock(
                      icon: '⚡',
                      title: 'Músculos Trabajados',
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: muscles
                            .map(
                              (muscle) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1D2A3A)
                                      : const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  muscle,
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF67B3FF)
                                        : const Color(0xFF1E3A8A),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    _ModalBlock(
                      icon: '🔧',
                      title: 'Equipamiento',
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: equipment
                            .map(
                              (tool) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2F2F2F)
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tool,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF374151),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    _ModalBlock(
                      icon: '⚠',
                      title: 'Consejos de Ejecución',
                      highlighted: true,
                      child: Text(
                        item.tips.isEmpty
                            ? 'Sin consejos registrados.'
                            : item.tips,
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.cardColor,
                          foregroundColor: theme.colorScheme.onSurface,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
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

class _ModalBlock extends StatelessWidget {
  const _ModalBlock({
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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : (isDark ? theme.cardColor : const Color(0xFFF3F4F6)),
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                icon,
                style: TextStyle(color: primary, fontSize: 14),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              fontSize: 13,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    this.backgroundColor = const Color(0xFF2A2A2A),
    this.textColor = AppColors.secondaryText,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w600,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    const lightEdge = Color(0xFFA6ADB5);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: isLight
            ? Border.all(color: lightEdge, width: 1.0)
            : null,
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

class _EmptyExercisesState extends StatelessWidget {
  const _EmptyExercisesState({required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.secondaryText,
            size: 34,
          ),
          SizedBox(height: 10),
          Text(
            'No encontramos ejercicios con esos filtros.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondaryText,
                ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onClearFilters,
            child: const Text('Restablecer busqueda'),
          ),
        ],
      ),
    );
  }
}
