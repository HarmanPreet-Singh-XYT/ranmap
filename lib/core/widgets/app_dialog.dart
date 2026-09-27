import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'brand/brand_sheet_surface.dart';
import '../theme/nav_palette.dart';

/// A ForUI-styled confirmation dialog.
///
/// Returns true when the user confirms, false on cancel/dismiss.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => BrandSheetSurface.dialog(
        child: _ConfirmContent(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive,
        ),
      ),
    ),
  );
  return result ?? false;
}

/// A ForUI-styled dialog that collects a single line of text.
///
/// Returns the trimmed value, or null when cancelled/dismissed.
Future<String?> showAppTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String confirmLabel = 'Create',
  String? initialValue,
  int? maxLength,
}) {
  return showFDialog<String>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => BrandSheetSurface.dialog(
        child: _TextContent(
          title: title,
          label: label,
          hint: hint,
          confirmLabel: confirmLabel,
          initialValue: initialValue,
          maxLength: maxLength,
        ),
      ),
    ),
  );
}

class _TextContent extends StatefulWidget {
  const _TextContent({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmLabel,
    required this.initialValue,
    required this.maxLength,
  });

  final String title;
  final String label;
  final String? hint;
  final String confirmLabel;
  final String? initialValue;
  final int? maxLength;

  @override
  State<_TextContent> createState() => _TextContentState();
}

class _TextContentState extends State<_TextContent> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: c.foreground,
            ),
          ),
          const SizedBox(height: 16),
          FTextField(
            control: FTextFieldControl.managed(controller: _controller),
            label: Text(widget.label),
            hint: widget.hint,
            autofocus: true,
            maxLength: widget.maxLength,
            onSubmit: (value) => Navigator.of(context).pop(value.trim()),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: .outline,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FButton(
                  onPress: () =>
                      Navigator.of(context).pop(_controller.text.trim()),
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmContent extends StatelessWidget {
  const _ConfirmContent({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: c.foreground,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: TextStyle(color: c.mutedForeground, height: 1.35),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: .outline,
                  onPress: () => Navigator.of(context).pop(false),
                  child: Text(cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FButton(
                  variant: destructive ? .destructive : .primary,
                  onPress: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
