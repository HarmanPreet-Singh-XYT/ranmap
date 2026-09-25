import 'package:flutter/material.dart';
// Hide geolocator's `Position`; `Position` here is the GeoJSON type from the
// map engine.
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/defaults.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/units.dart';
// `LocationSettings` collides with mapbox's; hide it so geolocator's is used.
import 'map_engine/map_engine.dart' hide LocationSettings;

/// Bottom sheet shown when choosing a teammate to navigate to: shows distance
/// and heading, with a button that hands off to the native Maps app for
/// turn-by-turn "navigate to friend" directions.
Future<void> showNavigateToMemberSheet(
  BuildContext context, {
  required Position destination,
  String? username,
  String? vehicleType,
}) {
  return showFSheet(
    context: context,
    side: FLayout.btt,
    builder: (context) => _NavigateToMemberSheet(
      destination: destination,
      username: username,
      vehicleType: vehicleType,
    ),
  );
}

class _NavigateToMemberSheet extends ConsumerStatefulWidget {
  const _NavigateToMemberSheet({required this.destination, this.username, this.vehicleType});

  final Position destination;
  final String? username;

  /// The current user's vehicle, used to pick a sensible hand-off mode.
  final String? vehicleType;

  @override
  ConsumerState<_NavigateToMemberSheet> createState() => _NavigateToMemberSheetState();
}

class _NavigateToMemberSheetState extends ConsumerState<_NavigateToMemberSheet> {
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
                locationSettings: const LocationSettings(timeLimit: kLocationFixTimeout),
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

  /// Google Maps understands driving/walking/bicycling/transit. A bicycle gets
  /// directions that respect it; every other vehicle (including scooters, which
  /// Google has no mode for) hands off as driving.
  String get _travelMode => switch (widget.vehicleType) {
        'bike' => 'bicycling',
        _ => 'driving',
      };

  Future<void> _openTurnByTurn() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${widget.destination.lat},${widget.destination.lng}'
      '&travelmode=$_travelMode',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final c = NavColors.of(context);
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.directions_car_filled_rounded, color: c.activeRoute),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username != null ? '@${widget.username}' : 'Teammate',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.foreground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _bearingDegrees == null
                            ? _distanceLabel(unit)
                            : '${_distanceLabel(unit)} · $_directionLabel',
                        style: TextStyle(fontSize: 15, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FButton(
              size: .lg,
              onPress: _openTurnByTurn,
              prefix: const Icon(Icons.navigation_rounded),
              child: const Text('Navigate to them'),
            ),
          ],
        ),
      ),
    );
  }
}
