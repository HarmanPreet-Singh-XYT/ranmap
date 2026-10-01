import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/brand_palette.dart';
import '../widgets/brand/brand_alert.dart';
import '../widgets/brand/brand_buttons.dart';

/// Shown after the OS has denied a permission (microphone, camera, location…).
///
/// A denial can't be re-prompted, so this gives the user a route back: an
/// "Open Settings" button that deep-links to the app's own settings page (where
/// they can flip the permission on), plus an optional retry the caller can use
/// to re-attempt the action once they return.
///
/// Opening the app's settings is platform-agnostic here — `Geolocator`'s
/// `openAppSettings()` opens this app's settings page regardless of which
/// permission it is (it isn't location-specific).
class AppPermissionHint extends StatelessWidget {
  const AppPermissionHint({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;

  /// Re-attempts the gated action (e.g. enabling the mic/camera) once the user
  /// comes back from Settings. Omit to show only "Open Settings".
  final Future<void> Function()? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandAlert(variant: BrandAlertVariant.info, message: message),
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              BrandSecondaryButton(
                label: 'Open Settings',
                expand: false,
                leading: const Icon(Icons.settings_rounded, size: 18),
                onPressed: () => Geolocator.openAppSettings(),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: BrandSpace.sm),
                BrandSecondaryButton(
                  label: retryLabel,
                  expand: false,
                  leading: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () => onRetry!(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
