import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// A soft, filled brand input (`h-14`, generously rounded) with a leading
/// glyph and an optional trailing action.
///
/// Idle it wears the warm grey `surface-container-low`; on focus it lifts to
/// pure white with a 2px grass-green ring — matching the design's focus state.
class BrandTextField extends StatefulWidget {
  const BrandTextField({
    super.key,
    required this.controller,
    this.hint,
    this.leadingIcon,
    this.trailing,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.maxLength,
    this.inputFormatters,
    this.radius = BrandRadii.fieldRadius,
    this.textAlign = TextAlign.start,
    this.style,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
  });

  /// Rows the field grows to. `1` keeps the fixed 56px pill; `> 1` lets the
  /// field grow (used by chat composers and notes).
  final int maxLines;
  final int? minLines;

  final TextEditingController controller;
  final String? hint;
  final IconData? leadingIcon;
  final Widget? trailing;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final BorderRadius radius;
  final TextAlign textAlign;
  final TextStyle? style;
  final bool enabled;

  @override
  State<BrandTextField> createState() => _BrandTextFieldState();
}

class _BrandTextFieldState extends State<BrandTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = (widget.style ?? BrandText.bodyMd).copyWith(
      color: BrandColors.onSurface,
    );
    // A single-line field is a fixed 56px pill; a multi-line one grows.
    final multiline = widget.maxLines > 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      constraints: multiline
          ? const BoxConstraints(minHeight: 56)
          : const BoxConstraints.tightFor(height: 56),
      decoration: BoxDecoration(
        color: _focused ? BrandColors.surface : BrandColors.surfaceContainerLow,
        borderRadius: widget.radius,
        border: _focused
            ? Border.all(color: BrandColors.primaryContainer, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (widget.leadingIcon != null)
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 2,
                top: multiline ? 17 : 0,
              ),
              child: Icon(
                widget.leadingIcon,
                size: 20,
                color: BrandColors.textMuted,
              ),
            ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofillHints,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              maxLength: widget.maxLength,
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              inputFormatters: widget.inputFormatters,
              textAlign: widget.textAlign,
              cursorColor: BrandColors.primaryContainer,
              style: textStyle,
              decoration: InputDecoration(
                isCollapsed: true,
                counterText: '',
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: (widget.style ?? BrandText.bodyMd).copyWith(
                  color: BrandColors.textMuted,
                ),
                contentPadding: EdgeInsets.only(
                  left: widget.leadingIcon != null ? 12 : 20,
                  right: widget.trailing != null ? 4 : 20,
                  top: multiline ? 18 : 0,
                  bottom: multiline ? 18 : 0,
                ),
              ),
            ),
          ),
          if (widget.trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: widget.trailing,
            ),
        ],
      ),
    );
  }
}

/// A round, icon-only tap target used inside and beside text fields.
class BrandFieldAction extends StatelessWidget {
  const BrandFieldAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        width: 40,
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: color ?? BrandColors.textMuted),
      ),
    );
  }
}
