import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/cloudinary_service.dart';
import '../../data/user_store.dart';
import '../../theme/app_theme.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late TextEditingController _nombreController;
  late TextEditingController _emailController;
  late TextEditingController _edadController;
  late TextEditingController _pesoController;
  late TextEditingController _alturaController;

  String _nivelSeleccionado = 'Principiante';
  final Set<String> _objetivosSeleccionados = {};
  String _fotoInicial = 'LL';
  Uint8List? _fotoBytes;
  String _fotoUrl = '';

  final List<String> _objetivos = [
    'Perder peso',
    'Ganar músculo',
    'Mantenimiento',
    'Aumentar fuerza',
    'Mejorar resistencia',
  ];

  final Map<String, String?> _errors = {
    'nombre': null,
    'email': null,
    'edad': null,
  };

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _emailController = TextEditingController();
    _edadController = TextEditingController();
    _pesoController = TextEditingController();
    _alturaController = TextEditingController();
    _loadFromStore();
  }

  void _loadFromStore() {
    final u = UserStore.instance.currentUser;
    _nombreController.text = u.name;
    _emailController.text = u.email;
    _edadController.text = u.age?.toString() ?? '';
    _pesoController.text = u.weightKg?.toString() ?? '';
    _alturaController.text = u.heightCm?.toString() ?? '';
    _nivelSeleccionado = u.level ?? 'Principiante';
    _objetivosSeleccionados
      ..clear()
      ..addAll(u.objectives);
    _fotoBytes = u.photoBytes;
    _fotoUrl = u.photoUrl;
    _updateFotoInicial();
  }

  void _updateFotoInicial() {
    final nombre = _nombreController.text.trim();
    if (nombre.isNotEmpty) {
      final parts = nombre.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        _fotoInicial = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        _fotoInicial = nombre.substring(0, 1).toUpperCase();
      }
    } else {
      _fotoInicial = 'LL';
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _edadController.dispose();
    _pesoController.dispose();
    _alturaController.dispose();
    super.dispose();
  }

  bool _validarNombre(String valor) {
    if (valor.trim().isEmpty) {
      _errors['nombre'] = 'El nombre es requerido';
      return false;
    }
    if (valor.trim().length < 3) {
      _errors['nombre'] = 'El nombre debe tener al menos 3 caracteres';
      return false;
    }
    _errors['nombre'] = null;
    return true;
  }

  bool _validarEmail(String valor) {
    if (valor.trim().isEmpty) {
      _errors['email'] = 'El email es requerido';
      return false;
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}\$');
    if (!emailRegex.hasMatch(valor.trim())) {
      _errors['email'] = 'Email inválido';
      return false;
    }
    _errors['email'] = null;
    return true;
  }

  bool _validarEdad(String valor) {
    if (valor.trim().isEmpty) {
      _errors['edad'] = 'La edad es requerida';
      return false;
    }
    final edad = int.tryParse(valor);
    if (edad == null || edad < 15 || edad > 100) {
      _errors['edad'] = 'Debe estar entre 15 y 100 años';
      return false;
    }
    _errors['edad'] = null;
    return true;
  }

  Future<void> _seleccionarFotoLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    setState(() => _fotoBytes = bytes);
    final url = await CloudinaryService.uploadImageBytes(
      bytes,
      fileName: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (!mounted) return;
    if (url != null && url.trim().isNotEmpty) {
      setState(() {
        _fotoUrl = url;
        _fotoBytes = null;
      });
      UserStore.instance.updateCurrentProfilePhotoUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil subida correctamente.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo subir la foto.')),
      );
    }
  }

  Future<void> _guardar() async {
    final nombreValido = _validarNombre(_nombreController.text);
    final emailValido = _validarEmail(_emailController.text);
    final edadValida = _validarEdad(_edadController.text);
    setState(() {});
    if (!(nombreValido && emailValido && edadValida)) return;

    final age = int.parse(_edadController.text.trim());
    final weight = double.tryParse(_pesoController.text.trim());
    final height = int.tryParse(_alturaController.text.trim());

    final current = UserStore.instance.currentUser;
    UserStore.instance.updateCurrentProfile(
      name: _nombreController.text.trim(),
      email: _emailController.text.trim(),
      age: age,
      level: _nivelSeleccionado,
      weightKg: weight,
      heightCm: height,
      objectives: _objetivosSeleccionados.toList(),
    );

    try {
      if (current.id.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(current.id)
            .set({
          'name': _nombreController.text.trim(),
          'email': _emailController.text.trim(),
          'age': age,
          'level': _nivelSeleccionado,
          'weightKg': weight,
          'heightCm': height,
          'objectives': _objetivosSeleccionados.toList(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil guardado.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: AppTheme.pageBackgroundFor(context),
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            onPressed: _guardar,
            tooltip: 'Guardar',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.78),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _fotoBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                _fotoBytes!,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                              ),
                            )
                          : _fotoUrl.trim().isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    _fotoUrl,
                                    width: 110,
                                    height: 110,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(
                                      _fotoInicial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 40,
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  _fotoInicial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 40,
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _seleccionarFotoLocal,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Cambiar foto'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildTextField(
              context,
              label: 'Nombre completo',
              controller: _nombreController,
              error: _errors['nombre'],
              onChanged: (_) => setState(_updateFotoInicial),
              onBlur: () => setState(() => _validarNombre(_nombreController.text)),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              label: 'Email',
              controller: _emailController,
              error: _errors['email'],
              keyboardType: TextInputType.emailAddress,
              onBlur: () => setState(() => _validarEmail(_emailController.text)),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              label: 'Edad',
              controller: _edadController,
              error: _errors['edad'],
              keyboardType: TextInputType.number,
              onBlur: () => setState(() => _validarEdad(_edadController.text)),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              context,
              label: 'Nivel de entrenamiento',
              value: _nivelSeleccionado,
              options: const ['Principiante', 'Intermedio', 'Avanzado'],
              onChanged: (v) => setState(() => _nivelSeleccionado = v),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              label: 'Peso (kg)',
              controller: _pesoController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              label: 'Altura (cm)',
              controller: _alturaController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            Text('Objetivos', style: theme.textTheme.titleMedium?.copyWith(color: onSurface)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _objetivos.map((o) {
                final selected = _objetivosSeleccionados.contains(o);
                return ChoiceChip(
                  label: Text(o),
                  selected: selected,
                  onSelected: (s) => setState(() {
                    if (s) _objetivosSeleccionados.add(o); else _objetivosSeleccionados.remove(o);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardar,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Guardar cambios', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? error,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    VoidCallback? onBlur,
  }) {
    final hasError = error != null && error.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onEditingComplete: onBlur,
          decoration: InputDecoration(
            hintText: label,
            errorText: error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.surfaceBorderFor(context)),
            color: Theme.of(context).cardColor,
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          ),
        ),
      ],
    );
  }
}
