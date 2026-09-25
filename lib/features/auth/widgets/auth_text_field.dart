import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// A labelled auth input. Password fields get a visibility toggle.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final control = FTextFieldControl.managed(controller: controller);

    if (obscureText) {
      return FTextField.password(
        control: control,
        label: Text(label),
        textInputAction: textInputAction ?? TextInputAction.done,
        autofillHints: autofillHints ?? const [AutofillHints.password],
        onSubmit: onSubmitted,
      );
    }

    return FTextField(
      control: control,
      label: Text(label),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmit: onSubmitted,
    );
  }
}
