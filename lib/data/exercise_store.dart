import 'package:flutter/foundation.dart';

// Modelo compartido entre admin y catálogo
class ExerciseEntry {
  ExerciseEntry({
    required this.name,
    required this.category,
    required this.equipment,
    required this.level,
    required this.description,
    this.muscles = const [],
    this.videoUrl = '',
    this.imageUrl = '',
    this.imageBytes,
    this.imageName = '',
    this.tips = '',
  });

  String name;
  String category;
  List<String> equipment;
  String level;
  String description;
  List<String> muscles;
  String videoUrl;
  String imageUrl;
  Uint8List? imageBytes;
  String imageName;
  String tips;

  /// Primera pieza de equipo como texto (para chips del catálogo)
  String get equipmentDisplay =>
      equipment.isEmpty ? 'Sin equipo' : equipment.join(', ');

  /// Músculo principal (usa muscles[0] si está definido, si no categoría)
  String get muscleFocus {
    if (muscles.isNotEmpty) return muscles.first;
    switch (category) {
      case 'Pecho':
        return 'Pectoral';
      case 'Espalda':
        return 'Dorsal';
      case 'Piernas':
        return 'Pierna completa';
      case 'Hombros':
        return 'Deltoides';
      case 'Brazos':
        return 'Biceps/Triceps';
      case 'Abdomen':
        return 'Core';
      case 'Cardio':
        return 'Resistencia';
      default:
        return 'Estabilidad';
    }
  }

  /// Descripción de músculos para el detalle
  String get musclesInvolved {
    if (muscles.isNotEmpty) return muscles.join(', ');
    switch (category) {
      case 'Pecho':
        return 'Pectoral mayor, deltoides anterior y triceps como apoyo.';
      case 'Espalda':
        return 'Dorsal ancho, romboides, trapecio medio y biceps como sinergista.';
      case 'Piernas':
        return 'Cuadriceps, gluteos, femorales y estabilizadores de cadera.';
      case 'Hombros':
        return 'Deltoides anterior/medio/posterior y manguito rotador.';
      case 'Brazos':
        return 'Biceps braquial, braquial anterior y triceps segun variante.';
      case 'Abdomen':
        return 'Recto abdominal, oblicuos y transverso para control del tronco.';
      case 'Cardio':
        return 'Participacion global con alto trabajo cardiorrespiratorio.';
      default:
        return 'Cadena posterior y core con foco en control y coordinacion.';
    }
  }
}

// ---------------------------------------------------------------------------
// Store singleton — única fuente de verdad para los ejercicios
// ---------------------------------------------------------------------------

class ExerciseStore extends ChangeNotifier {
  ExerciseStore._();

  static final ExerciseStore instance = ExerciseStore._();

  final List<ExerciseEntry> _exercises = [];

  List<ExerciseEntry> get exercises => List.unmodifiable(_exercises);

  void add(ExerciseEntry e) {
    _exercises.add(e);
    notifyListeners();
  }

  void update(int index, ExerciseEntry e) {
    _exercises[index] = e;
    notifyListeners();
  }

  void remove(int index) {
    _exercises.removeAt(index);
    notifyListeners();
  }

  void replaceAll(List<ExerciseEntry> items) {
    _exercises
      ..clear()
      ..addAll(items);
    notifyListeners();
  }
}
