import 'dart:ui';
import 'package:flutter/material.dart';

class CustomFilterDropdown extends StatelessWidget {
  final String value;
  final String hint;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? allLabel;

  const CustomFilterDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.allLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cellColor = theme.colorScheme.onSurface.withOpacity(0.06);
    return _DropdownButtonBlur(
      value: value,
      hint: hint,
      options: options,
      onChanged: onChanged,
      allLabel: allLabel,
      isDark: isDark,
      cellColor: cellColor,
    );
  }
}

class _DropdownButtonBlur extends StatefulWidget {
  final String value;
  final String hint;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? allLabel;
  final bool isDark;
  final Color cellColor;

  const _DropdownButtonBlur({
    required this.value,
    required this.hint,
    required this.options,
    required this.onChanged,
    this.allLabel,
    required this.isDark,
    required this.cellColor,
  });

  @override
  State<_DropdownButtonBlur> createState() => _DropdownButtonBlurState();
}

class _DropdownButtonBlurState extends State<_DropdownButtonBlur> {
  bool _isOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggleDropdown() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.black.withOpacity(0.75)
                        : Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.08),
                    ),
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      if (widget.allLabel != null)
                        _buildItem('', widget.allLabel!),
                      ...widget.options.map((option) => _buildItem(option, option)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isOpen = false);
  }

  Widget _buildItem(String value, String label) {
    final selected = widget.value == value;
    return InkWell(
      onTap: () {
        widget.onChanged(value);
        _removeOverlay();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: selected ? Colors.black.withOpacity(0.07) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark ? widget.cellColor : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.value.isEmpty
                      ? (widget.allLabel ?? widget.hint)
                      : widget.value,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.62),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
