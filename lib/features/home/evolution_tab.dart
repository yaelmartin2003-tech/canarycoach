import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// import '../../data/supabase_storage_service.dart';
import '../../data/cloudinary_service.dart';
import '../../data/user_store.dart';
import '../shared/photo_viewer_dialog.dart';
import '../../theme/app_theme.dart';

class EvolutionTab extends StatefulWidget {
  const EvolutionTab({
    super.key,
    this.userIndex,
    this.adminMode = false,
    this.allowCreateTests = true,
  });

  final int? userIndex;
  final bool adminMode;
  final bool allowCreateTests;

  @override
  State<EvolutionTab> createState() => _EvolutionTabState();
}

class _EvolutionTabState extends State<EvolutionTab> {
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
  void dispose() {
    super.dispose();
  }

  int? get _resolvedUserIndex {
    if (widget.userIndex != null) return widget.userIndex;
    final users = UserStore.instance.users;
    final current = UserStore.instance.currentUser;
    final index = users.indexWhere((user) => user.id == current.id);
    if (index == -1) return null;
    return index;
  }

  Future<void> _pickImage({
    required void Function(Uint8List bytes, String name) onPicked,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.first;
    final bytes = file?.bytes;
    if (bytes == null) return;
    onPicked(bytes, file?.name ?? 'imagen');
  }

  void _openPhotoViewer(
    BuildContext ctx,
    List<PhotoItem> photos,
    int initialIndex,
  ) {
    if (photos.isEmpty) return;
    showDialog<void>(
      context: ctx,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => PhotoViewerDialog(
        photos: photos,
        initialIndex: initialIndex.clamp(0, photos.length - 1),
      ),
    );
  }

  Future<void> _openCreateTestSheet({required int userIndex}) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    Uint8List? selectedImage;
    var selectedImageName = '';
    var selectedImageUrl = '';
    var isUploadingPhoto = false;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bottom = MediaQuery.of(sheetContext).viewInsets.bottom +
                MediaQuery.viewPaddingOf(sheetContext).bottom;
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(sheetContext),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: AppTheme.modalShadowFor(sheetContext),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottom),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nuevo test',
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleCtrl,
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                        decoration: _fieldDecoration('Titulo del test'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descCtrl,
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                        maxLines: 3,
                        decoration: _fieldDecoration('Descripcion del test'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: isUploadingPhoto
                            ? null
                            : () async {
                                await _pickImage(
                                  onPicked: (bytes, name) async {
                                    setSheetState(() {
                                      selectedImage = bytes;
                                      selectedImageName = name;
                                      selectedImageUrl = '';
                                      isUploadingPhoto = true;
                                    });
                                    final url = await CloudinaryService.uploadImageBytes(
                                      bytes,
                                      fileName:
                                          'evolution_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    );
                                    setSheetState(() {
                                      selectedImageUrl = url ?? '';
                                      isUploadingPhoto = false;
                                    });
                                    if ((url == null || url.isEmpty) && sheetContext.mounted) {
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Error subiendo la foto. Se guardará sin imagen.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        icon: const Icon(Icons.image_rounded),
                        label: isUploadingPhoto
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 8),
                                  Text('Subiendo foto…'),
                                ],
                              )
                            : const Text('Subir imagen'),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          selectedImageName.isEmpty
                              ? 'Imagen seleccionada'
                              : selectedImageName,
                          style: TextStyle(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurface.withValues(alpha: 0.62),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                selectedImage!,
                                height: 130,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (isUploadingPhoto)
                              const Positioned(
                                bottom: 6,
                                right: 8,
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                              ),
                            if (selectedImageUrl.isNotEmpty)
                              Positioned(
                                bottom: 6,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.cloud_done, color: Colors.greenAccent, size: 14),
                                      SizedBox(width: 4),
                                      Text('Subida', style: TextStyle(color: Colors.white, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (isSaving || isUploadingPhoto || (selectedImage != null && selectedImageUrl.isEmpty))
                              ? null
                              : () async {
                                  setSheetState(() => isSaving = true);
                                  final title = titleCtrl.text.trim();
                                  final desc = descCtrl.text.trim();
                                  if (title.isEmpty) {
                                    setSheetState(() => isSaving = false);
                                    return;
                                  }
                                  UserStore.instance.addEvolutionTestForUser(
                                    userIndex,
                                    title: title,
                                    description: desc,
                                    createdByAdmin: widget.adminMode,
                                    imageBytes: selectedImage,
                                    imageUrl: selectedImageUrl,
                                    imageName: selectedImageName,
                                  );
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text(
                            'Guardar test',
                            style: TextStyle(fontWeight: FontWeight.w800),
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
      },
    );
  }

  Future<void> _openAddEntrySheet({
    required int userIndex,
    required EvolutionTest test,
  }) async {
    final noteCtrl = TextEditingController();
    Uint8List? selectedImage;
    var selectedImageName = '';
    var selectedImageUrl = '';
    var isUploadingPhoto = false;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bottom = MediaQuery.of(sheetContext).viewInsets.bottom +
                MediaQuery.viewPaddingOf(sheetContext).bottom;
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.modalSurfaceFor(sheetContext),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: AppTheme.modalShadowFor(sheetContext),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottom),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nueva entrada en ${test.title}',
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteCtrl,
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                        maxLines: 3,
                        decoration: _fieldDecoration('Nota de progreso'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: (isUploadingPhoto || isSaving)
                            ? null
                            : () async {
                                await _pickImage(
                                  onPicked: (bytes, name) async {
                                    setSheetState(() {
                                      selectedImage = bytes;
                                      selectedImageName = name;
                                      selectedImageUrl = '';
                                      isUploadingPhoto = true;
                                    });
                                    final url =
                                        await CloudinaryService.uploadImageBytes(
                                      bytes,
                                      fileName:
                                          'evolution_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    );
                                    setSheetState(() {
                                      selectedImageUrl = url ?? '';
                                      isUploadingPhoto = false;
                                    });
                                    if ((url == null || url.isEmpty) &&
                                        sheetContext.mounted) {
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Error subiendo la foto. Se guardará sin imagen.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        icon: const Icon(Icons.photo_camera_back_rounded),
                        label: isUploadingPhoto
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Subiendo foto…'),
                                ],
                              )
                            : const Text('Añadir foto'),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(height: 8),
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                selectedImage!,
                                height: 130,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (selectedImageUrl.isNotEmpty)
                              Positioned(
                                bottom: 6,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.cloud_done,
                                          color: Colors.greenAccent, size: 14),
                                      SizedBox(width: 4),
                                      Text('Subida',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (isSaving || isUploadingPhoto)
                              ? null
                              : () {
                                  setSheetState(() => isSaving = true);
                                  UserStore.instance.addEvolutionTestEntryForUser(
                                    userIndex,
                                    testId: test.id,
                                    note: noteCtrl.text.trim(),
                                    imageBytes: selectedImage,
                                    imageUrl: selectedImageUrl,
                                    imageName: selectedImageName,
                                  );
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Colors.black,
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'Guardar entrada',
                                  style: TextStyle(fontWeight: FontWeight.w800),
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
      },
    );
  }

  void _openTestDetailSheet({
    required int userIndex,
    required EvolutionTest test,
    required AppUserData user,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.modalSurfaceFor(sheetContext),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: AppTheme.modalShadowFor(sheetContext),
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                final users = UserStore.instance.users;
                if (userIndex < 0 || userIndex >= users.length) {
                  return const SizedBox.shrink();
                }

                final currentUser = users[userIndex];
                final currentTest = currentUser.evolutionTests.firstWhere(
                  (item) => item.id == test.id,
                  orElse: () => test,
                );

                final sortedEntries = [...currentTest.entries]
                  ..sort((left, right) => right.date.compareTo(left.date));
                final photoItems = sortedEntries
                    .where(
                      (e) =>
                          e.imageBytes != null || e.imageUrl.trim().isNotEmpty,
                    )
                    .map(
                      (e) => PhotoItem(
                        bytes: e.imageBytes,
                        url: e.imageUrl,
                        label: _formatDateLong(e.date),
                      ),
                    )
                    .toList();
                final photoEntryIds = sortedEntries
                    .where(
                      (e) =>
                          e.imageBytes != null || e.imageUrl.trim().isNotEmpty,
                    )
                    .map((e) => e.id)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  children: [
                    Text(
                      currentTest.title,
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Usuario: ${currentUser.name}',
                      style: TextStyle(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                    if (currentTest.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        currentTest.description,
                        style: TextStyle(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurface.withValues(alpha: 0.68),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _openAddEntrySheet(
                            userIndex: userIndex,
                            test: currentTest,
                          );
                          if (!sheetContext.mounted) return;
                          setSheetState(() {});
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Añadir entrada al historial'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sortedEntries.isEmpty)
                      Text(
                        'Todavía no hay entradas en este test.',
                        style: TextStyle(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
                        ),
                      )
                    else
                      ...sortedEntries.map((entry) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(sheetContext).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.surfaceBorderFor(sheetContext),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDateLong(entry.date),
                                style: TextStyle(
                                  color: Theme.of(
                                    sheetContext,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (entry.note.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  entry.note,
                                  style: TextStyle(
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.68),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (entry.imageBytes != null ||
                                  entry.imageUrl.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    final idx = photoEntryIds.indexOf(entry.id);
                                    _openPhotoViewer(
                                      context,
                                      photoItems,
                                      idx < 0 ? 0 : idx,
                                    );
                                  },
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: entry.imageBytes != null
                                            ? Image.memory(
                                                entry.imageBytes!,
                                                width: double.infinity,
                                                height: 150,
                                                fit: BoxFit.cover,
                                              )
                                            : Image.network(
                                                entry.imageUrl,
                                                width: double.infinity,
                                                height: 150,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    const SizedBox(
                                                      height: 150,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                        ),
                                                      ),
                                                    ),
                                              ),
                                      ),
                                      const Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Icon(
                                          Icons.zoom_in_rounded,
                                          color: Colors.white70,
                                          size: 22,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.secondaryText),
      filled: true,
      fillColor: Theme.of(context).cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.surfaceBorderFor(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.surfaceBorderFor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final resolvedIndex = _resolvedUserIndex;
        if (resolvedIndex == null ||
            resolvedIndex < 0 ||
            resolvedIndex >= UserStore.instance.users.length) {
          return const SizedBox.shrink();
        }

        final user = UserStore.instance.users[resolvedIndex];

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cabecera ────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.adminMode ? 'Tests de ${user.name}' : 'Test personales',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.allowCreateTests)
                    FilledButton.icon(
                      onPressed: () => _openCreateTestSheet(userIndex: resolvedIndex),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nuevo test'),
                      style: FilledButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // ── Tests ───────────────────────────────────────────
              if (user.evolutionTests.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No hay tests creados aún.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                )
              else
                ...user.evolutionTests.map((test) {
                  final lastEntry = test.entries.isNotEmpty ? test.entries.last : null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(
                        test.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (test.description.isNotEmpty)
                            Text(
                              test.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            lastEntry != null
                                ? 'Última entrada: ${_formatDateLong(lastEntry.date)}'
                                : 'Sin entradas',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${test.entries.length} entradas',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _openTestDetailSheet(
                        userIndex: resolvedIndex,
                        test: test,
                        user: user,
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  String _formatDateLong(DateTime date) {
    return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
  }
}
