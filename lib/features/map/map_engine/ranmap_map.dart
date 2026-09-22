import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_style.dart';
import 'scene_3d.dart';
import 'vehicle_models.dart';

/// A Mapbox map pre-configured with ranmap's 3D scene (buildings, terrain,
/// time-of-day lighting) and the vehicle-owned location puck.
///
/// One-shot commands — recenter, switch basemap, toggle 3D/terrain — are
/// exposed on [RanmapMapViewState] through a [GlobalKey] rather than as
/// reactive props, since they're imperative actions, not state.
class RanmapMapView extends StatefulWidget {
  const RanmapMapView({
    super.key,
    required this.center,
    this.zoom = 15,
    this.pitch = 45,
    this.bearing = 0,
    this.style = RanmapMapStyle.standard,
    this.threeD = true,
    this.terrain = true,
    this.showUserLocation = false,
    this.userVehicleType,
    this.onMapReady,
    this.onStyleReady,
  });

  /// Initial camera center.
  final Position center;
  final double zoom;

  /// Tilt in degrees — non-zero is what makes the 3D scene read as 3D.
  final double pitch;
  final double bearing;
  final RanmapMapStyle style;

  /// Whether Mapbox Standard's extruded buildings/trees/landmarks are shown.
  final bool threeD;

  /// Whether the terrain DEM layer is enabled.
  final bool terrain;

  /// Whether to show the user's own location puck (needs location permission).
  final bool showUserLocation;

  /// When set, the puck is rendered as that vehicle's 3D model instead of the
  /// default 2D puck.
  final String? userVehicleType;

  /// Fired once the native map exists.
  final ValueChanged<MapboxMap>? onMapReady;

  /// Fired after each style load, once the 3D scene and puck have been applied.
  /// Sources/layers/annotations are dropped by a style (re)load, so screens
  /// re-apply their overlays here.
  final ValueChanged<MapboxMap>? onStyleReady;

  @override
  State<RanmapMapView> createState() => RanmapMapViewState();
}

class RanmapMapViewState extends State<RanmapMapView> {
  MapboxMap? _map;
  late RanmapMapStyle _style = widget.style;
  late bool _threeD = widget.threeD;
  late bool _terrain = widget.terrain;

  /// Built once, from the construction-time props. Mapbox treats a *changed*
  /// `viewport` as a request to re-position the camera, so reusing one instance
  /// is what keeps parent rebuilds (a position update, a provider change) from
  /// yanking the camera back to the initial center while the user is panning.
  late final ViewportState _viewport = CameraViewportState(
    center: Point(coordinates: widget.center),
    zoom: widget.zoom,
    pitch: widget.pitch,
    bearing: widget.bearing,
  );

  /// The live controller, or null before the platform view exists.
  MapboxMap? get map => _map;

  void _onMapCreated(MapboxMap map) {
    _map = map;
    widget.onMapReady?.call(map);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    await Scene3D.apply(map, buildings: _threeD, terrain: _terrain);
    await _applyLocationPuck(map);
    if (!mounted) return;
    widget.onStyleReady?.call(map);
  }

  Future<void> _applyLocationPuck(MapboxMap map) async {
    final vehicleType = widget.userVehicleType;
    try {
      await map.location.updateSettings(LocationComponentSettings(
        enabled: widget.showUserLocation,
        puckBearingEnabled: true,
        locationPuck: vehicleType == null
            ? null
            : LocationPuck(
                locationPuck3D: LocationPuck3D(
                  modelUri: VehicleModels.assetFor(vehicleType),
                  modelScale: const <double?>[1, 1, 1],
                  // Matches the SDK's default 3D-puck orientation; the puck
                  // then rotates this with the device heading.
                  modelRotation: const <double?>[0, 0, 90],
                ),
              ),
      ));
    } catch (_) {
      // The puck needs location permission; a failure here is non-fatal.
    }
  }

  /// Animates the camera to [center], optionally changing zoom.
  Future<void> flyTo(Position center, {double? zoom, double? pitch}) async {
    await _map?.flyTo(
      CameraOptions(
        center: Point(coordinates: center),
        zoom: zoom,
        pitch: pitch,
      ),
      MapAnimationOptions(duration: 900),
    );
  }

  /// Loads a different basemap. [onStyleReady] fires again once it's up, so
  /// callers re-apply their overlays there.
  Future<void> setStyle(RanmapMapStyle style) async {
    if (style == _style) return;
    setState(() => _style = style);
    await _map?.loadStyleURI(style.uri);
  }

  /// Toggles Mapbox Standard's 3D buildings/trees/landmarks.
  Future<void> setBuildings(bool enabled) async {
    setState(() => _threeD = enabled);
    final map = _map;
    if (map != null) {
      await Scene3D.applyStandard3d(
        map,
        buildings: enabled,
        lightPreset: Scene3D.lightPresetFor(DateTime.now()),
      );
    }
  }

  /// Toggles 3D terrain.
  Future<void> setTerrain(bool enabled) async {
    setState(() => _terrain = enabled);
    final map = _map;
    if (map != null) await Scene3D.setTerrain(map, enabled);
  }

  @override
  void didUpdateWidget(RanmapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final map = _map;
    if (map == null) return;

    // The user's vehicle can arrive after the map is up (the profile loads
    // asynchronously), so re-apply the puck when it changes.
    if (oldWidget.userVehicleType != widget.userVehicleType ||
        oldWidget.showUserLocation != widget.showUserLocation) {
      _applyLocationPuck(map);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapWidget(
      key: const ValueKey('ranmap-map'),
      styleUri: _style.uri,
      viewport: _viewport,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }
}
