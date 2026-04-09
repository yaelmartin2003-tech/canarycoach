import 'dart:typed_data';

import 'package:flutter/material.dart';

class PhotoItem {
  const PhotoItem({this.bytes, this.url = '', required this.label})
      : assert(bytes != null || url != '');

  final Uint8List? bytes;
  final String url;
  final String label;
}

class PhotoViewerDialog extends StatefulWidget {
  const PhotoViewerDialog({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  final List<PhotoItem> photos;
  final int initialIndex;

  @override
  State<PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<PhotoViewerDialog> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _ctrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xEE000000),
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final photo = widget.photos[i];
              return Center(
                child: InteractiveViewer(
                  child: photo.bytes != null
                      ? Image.memory(photo.bytes!, fit: BoxFit.contain)
                      : Image.network(
                          photo.url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                ),
              );
            },
          ),
          Positioned(
            top: 48,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.photos[_current].label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.photos.length > 1) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.photos.length, (i) {
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 250),
                          width: i == _current ? 20 : 8,
                          height: 6,
                          margin: EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _current
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white30,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.photos.length > 1 && _current > 0)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _ctrl.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.photos.length > 1 && _current < widget.photos.length - 1)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _ctrl.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
