import 'package:flutter/material.dart';
// Hide geolocator's `Position`; `Position` here is the GeoJSON type from the
// map engine.
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/constants/defaults.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/units.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
// `LocationSettings` collides with mapbox's; hide it so geolocator's is used.
import '../social/user_profile_screen.dart';
import 'map_engine/map_engine.dart' hide LocationSettings;

/// Bottom sheet shown when choosing a teammate to navigate to: shows distance
/// and heading, with a button that hands off to the native Maps app for
/// turn-by-turn "navigate to friend" directions.
Future<void> showNavigateToMemberSheet(
  BuildContext context, {
  required Position destination,
  String? username,
  String? userId,
  String? vehicleType,
  required VoidCallback onNavigate,
  VoidCallback? onShow,
  VoidCallback? onToggleFollow,
  bool following = false,
}) {
  return showFSheet(
    context: context,
    side: FLayout.btt,
    builder: (context) => _NavigateToMemberSheet(
      destination: destination,
      username: username,
      userId: userId,
      vehicleType: vehicleType,
      onNavigate: onNavigate,
      onShow: onShow,
      onToggleFollow: onToggleFollow,
      following: following,
    ),
  );
}

class _NavigateToMemberSheet extends ConsumerStatefulWidget {
  const _NavigateToMemberSheet({
    required this.destination,
    this.username,
    this.userId,
    this.vehicleType,
    required this.onNavigate,
    this.onShow,
    this.onToggleFollow,
    this.following = false,
  });

  /// Routes to them on the in-app map.
  final VoidCallback onNavigate;

  /// Centres the map on them / locks the camera onto them. Null hides the
  /// action (callers without a live map to drive).
  final VoidCallback? onShow;
  final VoidCallback? onToggleFollow;
  final bool following;

  final Position destination;
  final String? username;

  /// When set, the header opens this person's profile.
  final String? userId;

  /// The current user's vehicle.
  final String? vehicleType;

  @override
  ConsumerState<_NavigateToMemberSheet> createState() =>
      _NavigateToMemberSheetState();
}

class _NavigateToMemberSheetState
    extends ConsumerState<_NavigateToMemberSheet> {
  double? _distanceMeters;
  double? _bearingDegrees;

  @override
  void initState() {
    super.initState();
    _computeDistance();
  }

  Future<void> _computeDistance() async {
    try {
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: kLocationFixTimeout,
            ),
          );
      if (!mounted) return;
      setState(() {
        _distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          widget.destination.lat.toDouble(),
          widget.destination.lng.toDouble(),
        );
        _bearingDegrees = Geolocator.bearingBetween(
          position.latitude,
          position.longitude,
          widget.destination.lat.toDouble(),
          widget.destination.lng.toDouble(),
        );
      });
    } catch (_) {
      // Location unavailable — leave "Calculating…" instead of throwing an
      // unhandled error while the sheet is open.
      if (mounted) setState(() => _distanceMeters = null);
    }
  }

  String _distanceLabel(DistanceUnit unit) {
    final meters = _distanceMeters;
    if (meters == null) return 'Calculating…';
    return formatShortDistance(meters, unit);
  }

  String get _directionLabel {
    final bearing = _bearingDegrees;
    if (bearing == null) return '';
    final normalized = (bearing + 360) % 360;
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((normalized + 22.5) ~/ 45) % 8;
    return labels[index];
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    return BrandSheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.userId == null
                ? null
                : () {
                    final id = widget.userId!;
                    final nav = Navigator.of(context);
                    nav.pop();
                    nav.push(
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: id),
                      ),
                    );
                  },
            child: Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: BrandColors.accentMint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car_filled_rounded,
                    color: BrandColors.primary,
                  ),
                ),
                const SizedBox(width: BrandSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username != null
                            ? '@${widget.username}'
                            : 'Teammate',
                        style: BrandText.titleMd.copyWith(
                          color: BrandColors.textHeadline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _bearingDegrees == null
                            ? _distanceLabel(unit)
                            : '${_distanceLabel(unit)} · $_directionLabel',
                        style: BrandText.bodyMd.copyWith(
                          color: BrandColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Navigate to them',
            leadingIcon: Icons.navigation_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onNavigate();
            },
          ),
          if (widget.onToggleFollow != null) ...[
            const SizedBox(height: BrandSpace.sm),
            BrandSecondaryButton(
              label: widget.following ? 'Stop following' : 'Lock on',
              leading: Icon(
                widget.following
                    ? Icons.location_disabled_rounded
                    : Icons.my_location_rounded,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onToggleFollow!();
              },
            ),
          ],
          if (widget.onShow != null) ...[
            const SizedBox(height: BrandSpace.sm),
            BrandSecondaryButton(
              label: 'Show on map',
              onPressed: () {
                Navigator.of(context).pop();
                widget.onShow!();
              },
            ),
          ],
        ],
      ),
    );
  }
}
