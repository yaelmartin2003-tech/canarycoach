import 'package:flutter/material.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Aquí mostrar el modal para crear ejercicio
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const CreateExerciseModal(),
            );
          },
          child: const Text('Crear Ejercicio'),
        ),
      ),
    );
  }
}

class CreateExerciseModal extends StatefulWidget {
  const CreateExerciseModal({super.key});

  @override
  CreateExerciseModalState createState() => CreateExerciseModalState();
}

class CreateExerciseModalState extends State<CreateExerciseModal> {
  // Controladores y variables para los campos
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController videoUrlController = TextEditingController();
  final TextEditingController tipsController = TextEditingController();
  final TextEditingController otherMuscleController = TextEditingController();
  final TextEditingController otherEquipmentController = TextEditingController();

  String selectedDifficulty = 'Principiante';
  String selectedCategory = 'Pecho';

  List<String> selectedMuscles = [];
  List<String> selectedEquipment = [];

  final List<String> difficulties = ['Principiante', 'Intermedio', 'Avanzado'];
  final List<String> categories = ['Pecho', 'Espalda', 'Piernas', 'Hombros', 'Brazos', 'Abdomen', 'Cardio', 'Funcional'];
  final List<String> muscles = ['Pectorales', 'Deltoides', 'Bíceps', 'Tríceps', 'Dorsales', 'Trapecio', 'Cuádriceps', 'Isquiotibiales', 'Glúteos', 'Gemelos', 'Abdominales', 'Core'];

  final List<String> equipment = ['Ninguno', 'Mancuernas', 'Barra', 'Máquina', 'Polea', 'Banda elástica', 'Kettlebell', 'TRX'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezado
              const Text(
                'Crear Nuevo Ejercicio',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Divider(color: Colors.grey),

              // Nombre del Ejercicio
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Nombre del Ejercicio'),
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Ej: Press banca',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Desplegables: Categoría y Dificultad
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Categoría'),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          items: categories.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedCategory = newValue!;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dificultad'),
                        DropdownButtonFormField<String>(
                          initialValue: selectedDifficulty,
                          items: difficulties.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedDifficulty = newValue!;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Descripción
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Descripción del Ejercicio'),
              ),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe cómo realizar el ejercicio...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Grupos Musculares
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Grupos Musculares'),
              ),
              Wrap(
                spacing: 8.0,
                children: muscles.map((muscle) {
                  return FilterChip(
                    label: Text(muscle),
                    selected: selectedMuscles.contains(muscle),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedMuscles.add(muscle);
                        } else {
                          selectedMuscles.remove(muscle);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: otherMuscleController,
                      decoration: const InputDecoration(
                        hintText: 'Otro músculo...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (otherMuscleController.text.isNotEmpty) {
                        setState(() {
                          selectedMuscles.add(otherMuscleController.text);
                          otherMuscleController.clear();
                        });
                      }
                    },
                    child: const Text('Añadir'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Equipamiento
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Equipamiento'),
              ),
              Wrap(
                spacing: 8.0,
                children: equipment.map((eq) {
                  return FilterChip(
                    label: Text(eq),
                    selected: selectedEquipment.contains(eq),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedEquipment.add(eq);
                        } else {
                          selectedEquipment.remove(eq);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: otherEquipmentController,
                      decoration: const InputDecoration(
                        hintText: 'Otro equipamiento...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (otherEquipmentController.text.isNotEmpty) {
                        setState(() {
                          selectedEquipment.add(otherEquipmentController.text);
                          otherEquipmentController.clear();
                        });
                      }
                    },
                    child: const Text('Añadir'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // URL del Video
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('URL del Video (opcional)'),
              ),
              TextField(
                controller: videoUrlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Imagen del Ejercicio (placeholder)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Imagen del Ejercicio'),
              ),
              // Aquí podrías agregar un widget para subir imagen, pero por simplicidad, un placeholder
              Container(
                height: 100,
                color: Colors.grey[200],
                child: const Center(child: Text('Subir Imagen')),
              ),
              const SizedBox(height: 16),

              // Consejos de Ejecución
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Consejos de Ejecución'),
              ),
              TextField(
                controller: tipsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Consejos importantes...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              const Divider(color: Colors.grey),

              // Botones
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // Mostrar diálogo de confirmación
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('¿Estás seguro?'),
                            content: const Text('¿Quieres cancelar la creación del ejercicio?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop(); // Cerrar diálogo
                                  Navigator.of(context).pop(); // Cerrar modal
                                },
                                child: const Text('Sí'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Cerrar'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Aquí agregar lógica para crear el ejercicio
                        // Por ejemplo, guardar en una base de datos o lista
                        // Luego cerrar el modal
                        Navigator.of(context).pop();
                        // Mostrar mensaje de éxito o algo
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ejercicio creado')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Crear'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}