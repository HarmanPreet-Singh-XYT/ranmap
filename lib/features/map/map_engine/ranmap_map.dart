import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/theme/brand_palette.dart';
import 'map_style.dart';
import 'mapbox_token.dart';
import 'scene_3d.dart';
import 'vehicle_models.dart';

/// A Mapbox map pre-configured with ranmap's 3D scene (buildings, terrain,
/// time-of-day lighting) and the vehicle-owned location puck.
///
/// One-shot commands — recenter, switch basemap, toggle 3D/terrain — are
/// exposed on [RanmapMapViewState] through a [GlobalKey] rather than as
/// reactive props, since they're imperative actions, not state.
class RanmapMapView extends ConsumerStatefulWidget {
  const RanmapMapView({
    super.key,
    this.center,
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
    this.onCameraChanged,
  });

  /// Initial camera center. Null leaves the camera at Mapbox's default position
  /// (pair it with a wide [zoom]) when the user's location isn't known yet.
  final Position? center;
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

  /// Fired continuously while the camera moves (pan/zoom/animation).
  final ValueChanged<CameraChangedEventData>? onCameraChanged;

  @override
  ConsumerState<RanmapMapView> createState() => RanmapMapViewState();
}

class RanmapMapViewState extends ConsumerState<RanmapMapView> {
  MapboxMap? _map;

  /// Guards the map-token refresh timer, and remembers which token is applied
  /// so a refresh can be told apart from the initial load.
  Timer? _refreshTimer;
  String? _appliedToken;
  late RanmapMapStyle _style = widget.style;
  late bool _threeD = widget.threeD;
  late bool _terrain = widget.terrain;

  /// Built once, from the construction-time props. Mapbox treats a *changed*
  /// `viewport` as a request to re-position the camera, so reusing one instance
  /// is what keeps parent rebuilds (a position update, a provider change) from
  /// yanking the camera back to the initial center while the user is panning.
  late final ViewportState _viewport = CameraViewportState(
    center: widget.center == null ? null : Point(coordinates: widget.center!),
    zoom: widget.zoom,
    pitch: widget.pitch,
    bearing: widget.bearing,
  );

  /// The live controller, or null before the platform view exists.
  MapboxMap? get map => _map;

  void _onMapCreated(MapboxMap map) {
    _map = map;
    unawaited(_applyOrnaments(map));
    widget.onMapReady?.call(map);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    await Scene3D.apply(
      map,
      buildings: _threeD,
      terrain: _terrain,
      dark: _dark,
    );
    await _applyLocationPuck(map);
    await _applyOrnaments(map);
    if (!mounted) return;
    widget.onStyleReady?.call(map);
  }

  /// The live top system inset (status bar / notch), in logical pixels. The map
  /// is full-bleed under it and FScaffold adds no header here, so Mapbox's own
  /// ornaments must be pushed below it or the scale bar draws over the status
  /// bar. MediaQuery's padding can be zeroed by an ancestor scaffold, so the
  /// real window inset is also read from the view.
  double _topSafeInset() {
    final view = View.of(context);
    return math.max(
      MediaQuery.paddingOf(context).top,
      view.padding.top / view.devicePixelRatio,
    );
  }

  /// Nudges Mapbox's built-in ornaments clear of the system bars. Applied on
  /// every (re)load, since a style change recreates them.
  Future<void> _applyOrnaments(MapboxMap map) async {
    try {
      await map.scaleBar.updateSettings(
        ScaleBarSettings(marginTop: _topSafeInset() + 8, marginLeft: 12),
      );
    } catch (_) {
      // Ornaments are decorative; a failure here must not take the map down.
    }
  }

  /// The old hand-rolled vehicle models crashed Mapbox's model parser (null
  /// deref in MapboxCoreMaps on `com.mapbox.threadpool`) on the iOS simulator
  /// and on real devices. The models were regenerated with indexed geometry and
  /// UVs; this is back on to verify that. If it crashes again, set it to false
  /// and the default 2D puck is used.
  static const bool _use3dPuck = true;

  Future<void> _applyLocationPuck(MapboxMap map) async {
    final vehicleType = widget.userVehicleType;
    try {
      await map.location.updateSettings(
        LocationComponentSettings(
          enabled: widget.showUserLocation,
          puckBearingEnabled: true,
          // Face where the phone points (compass); the headlight beam follows
          // the same compass heading, so the two agree.
          puckBearing: PuckBearing.HEADING,
          // A soft pulsing halo (in screen pixels) so the vehicle stands out from
          // the map tiles.
          pulsingEnabled: true,
          pulsingColor: BrandColors.primary.withValues(alpha: 0.45).toARGB32(),
          pulsingMaxRadius: 60,
          locationPuck: !_use3dPuck || vehicleType == null
              ? null
              : LocationPuck(
                  locationPuck3D: LocationPuck3D(
                    modelUri: VehicleModels.assetFor(vehicleType),
                    // The puck scales in the viewport by default, so this is
                    // pixels per model unit (metre): 1 would draw a 4 m car
                    // ~4 px wide. ~11 px/m makes a car ~50 px on screen at any
                    // zoom.
                    modelScale: const <double?>[11, 11, 11],
                    // The models face +X. +90 rendered them facing the wrong
                    // way (tail toward the headlight beam), so yaw -90 instead;
                    // the puck then rotates this with the device heading.
                    modelRotation: const <double?>[0, 0, -90],
                  ),
                ),
        ),
      );
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
        lightPreset: Scene3D.lightPresetFor(DateTime.now(), dark: _dark),
      );
    }
  }

  /// Toggles 3D terrain.
  Future<void> setTerrain(bool enabled) async {
    setState(() => _terrain = enabled);
    final map = _map;
    if (map != null) await Scene3D.setTerrain(map, enabled);
  }

  bool get _dark => Theme.brightnessOf(context) == Brightness.dark;

  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.brightnessOf(context);
    final changed = _lastBrightness != null && _lastBrightness != brightness;
    _lastBrightness = brightness;
    final map = _map;
    if (changed && map != null) {
      unawaited(
        Scene3D.applyStandard3d(
          map,
          buildings: _threeD,
          lightPreset: Scene3D.lightPresetFor(
            DateTime.now(),
            dark: brightness == Brightness.dark,
          ),
        ),
      );
    }
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
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Refreshes the vendored token shortly before it expires. The lead time is
  /// deliberately shorter than the server's own refresh margin, so a refresh
  /// always lands on a freshly minted token rather than looping on a stale one.
  void _armRefresh(MapboxToken token) {
    _refreshTimer?.cancel();
    final until =
        token.expiresAt.difference(DateTime.now()) - const Duration(minutes: 2);
    _refreshTimer = Timer(until.isNegative ? Duration.zero : until, () {
      if (mounted) ref.invalidate(mapboxTokenProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The map can't render without a token, so gate on the vendored one: show a
    // spinner while it loads and a retry on failure, rather than a blank map.
    return ref
        .watch(mapboxTokenProvider)
        .when(
          loading: () => const Center(child: FCircularProgress()),
          error: (_, _) => _MapTokenError(
            onRetry: () => ref.invalidate(mapboxTokenProvider),
          ),
          data: (token) {
            if (_appliedToken != token.token) {
              _appliedToken = token.token;
              _armRefresh(token);
              // On a refresh (a new token after the map already exists) reload the
              // style so tile requests pick up the new token. On first load the map
              // is still null, and the token was already installed by the provider.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _map?.loadStyleURI(widget.style.uri);
              });
            }
            return MapWidget(
              key: const ValueKey('ranmap-map'),
              styleUri: _style.uri,
              viewport: _viewport,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onCameraChangeListener: (data) =>
                  widget.onCameraChanged?.call(data),
            );
          },
        );
  }
}

/// Shown in place of the map when the rendering token can't be fetched.
class _MapTokenError extends StatelessWidget {
  const _MapTokenError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('Could not load the map.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FButton(onPress: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
