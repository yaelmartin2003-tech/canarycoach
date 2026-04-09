import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class KeyboardInputPreview extends StatefulWidget {
  const KeyboardInputPreview({
    super.key,
    required this.text,
    this.visible = true,
    this.onTap,
    this.maxLines = 2,
    this.height = 58.0,
  });

  final String text;
  final bool visible;
  final VoidCallback? onTap;
  final int maxLines;
  final double height;

  @override
  State<KeyboardInputPreview> createState() => _KeyboardInputPreviewState();
}

class _KeyboardInputPreviewState extends State<KeyboardInputPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;
  late final AnimationController _caret;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _offset = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

    _caret = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _caret.repeat(reverse: true);

    if (widget.visible) _anim.forward();
  }

  @override
  void didUpdateWidget(covariant KeyboardInputPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _anim.forward();
      _caret.repeat(reverse: true);
    } else if (!widget.visible && oldWidget.visible) {
      _anim.reverse();
      _caret.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _caret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final borderColor = AppTheme.surfaceBorderFor(context);

    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _opacity,
        child: GestureDetector(
          onTap: widget.onTap,
          child: IgnorePointer(
            ignoring: widget.onTap == null,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: widget.height,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.cardColor.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: AppTheme.surfaceShadowFor(context, alpha: 0.06, blurRadius: 10, offsetY: 6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Caret
                    FadeTransition(
                      opacity: _caret,
                      child: Container(
                        width: 3,
                        height: widget.height - 22,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.text.isEmpty ? 'Escribe...' : widget.text,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                        ),
                        maxLines: widget.maxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Small send preview icon (visual hint)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.visibility, size: 18, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
