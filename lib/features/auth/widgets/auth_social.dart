import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../../../core/theme/brand_palette.dart';
import '../../../core/theme/brand_typography.dart';
import '../../../core/widgets/brand/brand_buttons.dart';
import '../../../core/widgets/brand/brand_icons.dart';

/// The `——— OR CONTINUE WITH ———` rule between the form and the social row.
class AuthSocialDivider extends StatelessWidget {
  const AuthSocialDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: BrandColors.surfaceContainerHigh, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR CONTINUE WITH',
            style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
          ),
        ),
        Expanded(
          child: Divider(color: BrandColors.surfaceContainerHigh, thickness: 1),
        ),
      ],
    );
  }
}

/// The Google / Apple social row shared by the sign-in and create-account
/// screens, so both offer the same providers.
class AuthSocialButtons extends StatelessWidget {
  const AuthSocialButtons({
    super.key,
    required this.onProvider,
    this.busy = false,
  });

  final ValueChanged<OAuthProvider> onProvider;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: BrandSecondaryButton(
            label: 'Google',
            leading: const GoogleGlyph(size: 18),
            onPressed: busy ? null : () => onProvider(OAuthProvider.google),
          ),
        ),
        const SizedBox(width: BrandSpace.gutterSm),
        Expanded(
          child: BrandSecondaryButton(
            label: 'Apple',
            leading: const AppleGlyph(size: 18),
            onPressed: busy ? null : () => onProvider(OAuthProvider.apple),
          ),
        ),
      ],
    );
  }
}
