import 'package:flutter/material.dart';
// Hide geolocator's `Position`; `Position` here is the GeoJSON type from the
// map engine.
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
// `LocationSettings` collides with mapbox's; hide it so geolocator's is used.
import 'map_engine/map_engine.dart' hide LocationSettings;

/// Bottom sheet shown when choosing a teammate to navigate to: shows distance
/// and heading, with a button that hands off to the native Maps app for
/// turn-by-turn "navigate to friend" directions.
Future<void> showNavigateToMemberSheet(
  BuildContext context, {
  required Position destination,
  String? username,
}) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _NavigateToMemberSheet(destination: destination, username: username),
  );
}

class _NavigateToMemberSheet extends StatefulWidget {
  const _NavigateToMemberSheet({required this.destination, this.username});

  final Position destination;
  final String? username;

  @override
  State<_NavigateToMemberSheet> createState() => _NavigateToMemberSheetState();
}

class _NavigateToMemberSheetState extends State<_NavigateToMemberSheet> {
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
                locationSettings: const LocationSettings(timeLimit: Duration(seconds: 15)),
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

  Future<void> _openTurnByTurn() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${widget.destination.lat},${widget.destination.lng}'
      '&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String get _distanceLabel {
    final meters = _distanceMeters;
    if (meters == null) return 'Calculating…';
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppTheme.primaryContainer,
                  child: Icon(Icons.directions_car_filled_rounded, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username != null ? '@${widget.username}' : 'Teammate',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _bearingDegrees == null ? _distanceLabel : '$_distanceLabel · $_directionLabel',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openTurnByTurn,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Navigate to them'),
            ),
          ],
        ),
      ),
    );
  }
}
