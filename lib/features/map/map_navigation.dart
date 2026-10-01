import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A destination handed to the map for in-app turn-by-turn style directions
/// (route drawn on the map, ETA, alternatives) — so tapping "directions"
/// anywhere in the app stays in Ranmap instead of bouncing to Google Maps.
class MapNavTarget {
  const MapNavTarget({
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String name;
  final double lat;
  final double lng;
}

/// A pending request for the map tab to start navigating. The home shell
/// switches to the map and [MapScreen] consumes (clears) it.
final mapNavRequestProvider = StateProvider<MapNavTarget?>((ref) => null);

/// Opens the map and routes to [name] at ([lat], [lng]), closing any screens
/// stacked on top of the home shell first.
void navigateInApp(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required double lat,
  required double lng,
}) {
  ref.read(mapNavRequestProvider.notifier).state = MapNavTarget(
    name: name,
    lat: lat,
    lng: lng,
  );
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
}
