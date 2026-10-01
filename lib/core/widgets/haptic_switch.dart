import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../feedback/app_feedback.dart';

/// An [FSwitch] that ticks when flipped, so every toggle in the app feels the
/// same.
class HapticSwitch extends StatelessWidget {
  const HapticSwitch({
    super.key,
    required this.value,
    required this.onChange,
    this.label,
  });

  final Widget? label;

  final bool value;
  final ValueChanged<bool>? onChange;

  @override
  Widget build(BuildContext context) {
    return FSwitch(
      label: label,
      value: value,
      onChange: onChange == null
          ? null
          : (v) {
              AppFeedback.selection();
              onChange!(v);
            },
    );
  }
}
