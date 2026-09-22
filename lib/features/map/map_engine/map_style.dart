import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// The selectable basemaps for the map.
///
/// The two Standard styles carry Mapbox's full 3D environment — extruded
/// buildings, trees, landmarks, terrain, and time-of-day lighting — configured
/// through [Scene3D]. The classic styles (Outdoors) have no such import; there
/// the 3D scene falls back to the explicit terrain layer only.
enum RanmapMapStyle {
  standard('Standard', Icons.layers_rounded, MapboxStyles.STANDARD),
  satellite('Satellite', Icons.satellite_alt_rounded, MapboxStyles.STANDARD_SATELLITE),
  outdoors('Outdoors', Icons.terrain_rounded, MapboxStyles.OUTDOORS);

  const RanmapMapStyle(this.label, this.icon, this.uri);

  final String label;
  final IconData icon;

  /// The `mapbox://styles/…` URI handed to the SDK.
  final String uri;

  /// Whether this style exposes the Mapbox Standard style import (`basemap`)
  /// that 3D buildings / lighting are configured through.
  bool get isStandard => this == standard || this == satellite;

  /// The next basemap in the cycle, for the layers button.
  RanmapMapStyle get next =>
      RanmapMapStyle.values[(index + 1) % RanmapMapStyle.values.length];
}
