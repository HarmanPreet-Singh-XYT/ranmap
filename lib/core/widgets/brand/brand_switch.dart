import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';

/// The brand pill switch: a soft track that slides a white knob over to grass
/// green when enabled.
class BrandSwitch extends StatelessWidget {
  const BrandSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: value
              ? BrandColors.primaryContainer
              : BrandColors.neutralHover,
          borderRadius: BrandRadii.pill,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            height: 20,
            width: 20,
            decoration: BoxDecoration(
              color: BrandColors.surface,
              shape: BoxShape.circle,
              boxShadow: BrandShadows.subtle,
            ),
          ),
        ),
      ),
    );
  }
}
