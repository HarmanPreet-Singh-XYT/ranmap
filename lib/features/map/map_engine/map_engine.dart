import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/constants/env.dart';

/// Re-exported so screens depend on the engine directory rather than reaching
/// into the SDK package directly (GeoJSON `Position`/`Point`, annotation
/// managers, `MapboxMap`, the layer/source types).
export 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

export 'geo.dart';
export 'map_markers.dart';
export 'map_style.dart';
export 'ranmap_map.dart';
export 'scene_3d.dart';
export 'vehicle_models.dart';

/// Entry point for the map engine (Mapbox Maps SDK for Flutter).
///
/// The app migrated off `google_maps_flutter` for a real 3D layer — extruded
/// buildings, terrain, and custom 3D vehicle models. Everything engine-specific
/// lives under this directory: screens talk to [RanmapMapView] and the small
/// helpers here rather than to the SDK directly.
abstract final class MapEngine {
  const MapEngine._();

  /// Installs the Mapbox access token. Must run before any map is built — call
  /// it once from `main` after the `.env` file is loaded.
  static void bootstrap() {
    MapboxOptions.setAccessToken(Env.mapboxAccessToken);
  }
}
