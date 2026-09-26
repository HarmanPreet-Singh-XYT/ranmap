import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// A soft, rounded inline banner for form errors and informational notes —
/// the brand-surface counterpart to Forui's `FAlert`, so screens never fall
/// back to a dark-theme alert on the white canvas.
class BrandAlert extends StatelessWidget {
  const BrandAlert({
    super.key,
    required this.message,
    this.variant = BrandAlertVariant.error,
  });

  final String message;
  final BrandAlertVariant variant;

  @override
  Widget build(BuildContext context) {
    final isError = variant == BrandAlertVariant.error;
    final bg = isError
        ? BrandColors.errorContainer
        : BrandColors.secondaryContainer;
    final fg = isError
        ? BrandColors.onErrorContainer
        : BrandColors.onSecondaryFixedVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BrandRadii.cardRadius),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: BrandText.bodySm.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

enum BrandAlertVariant { error, info }
