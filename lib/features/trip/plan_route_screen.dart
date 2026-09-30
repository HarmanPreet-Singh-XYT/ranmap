import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/constants/defaults.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../data/models/route_option.dart';
import '../../data/models/trip.dart';
import '../../data/services/google_maps_api_service.dart';
// `LocationSettings` collides with mapbox's; hide it so geolocator's is used.
import '../map/map_engine/map_engine.dart' hide LocationSettings;
import '../map/pick_location_screen.dart';

/// The result of planning a route: origin/destination points + names, and
/// the chosen route's encoded polyline.
class PlannedRoute {
  final String originName;
  final LatLngPoint originPoint;
  final String destinationName;
  final LatLngPoint destinationPoint;
  final String routePolyline;

  const PlannedRoute({
    required this.originName,
    required this.originPoint,
    required this.destinationName,
    required this.destinationPoint,
    required this.routePolyline,
  });
}

/// Pick an origin and destination, fetch route alternatives from the
/// Directions API, preview them on the map, and choose one.
class PlanRouteScreen extends StatefulWidget {
  const PlanRouteScreen({
    super.key,
    this.title = 'Plan route',
    this.initialOrigin,
    this.initialDestination,
  });

  final String title;

  /// Pre-filled endpoints when re-planning an existing trip. With no
  /// [initialOrigin] the origin defaults to the traveller's current position.
  final PickedLocation? initialOrigin;
  final PickedLocation? initialDestination;

  @override
  State<PlanRouteScreen> createState() => _PlanRouteScreenState();
}

class _PlanRouteScreenState extends State<PlanRouteScreen> {
  final _mapKey = GlobalKey<RanmapMapViewState>();

  Position? _origin;
  Position? _destination;
  String? _originName;
  String? _destinationName;
  List<RouteOption> _routes = const [];
  int _selectedRoute = 0;
  bool _loadingLocation = true;
  bool _fetchingRoutes = false;
  String? _error;

  /// Bumped whenever the endpoints change or a fetch starts; a response whose
  /// token is no longer current belongs to an old origin/destination and is
  /// discarded, so a slow reply can't attach routes to the wrong trip.
  int _fetchToken = 0;

  PointAnnotationManager? _pins;
  PolylineAnnotationManager? _lines;
  Uint8List? _originPin;
  Uint8List? _destinationPin;
  String? _renderedPinKey;
  String? _renderedRouteKey;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination?.position;
    _destinationName = widget.initialDestination?.name;
    final origin = widget.initialOrigin;
    if (origin != null) {
      _origin = origin.position;
      _originName = origin.name;
      _loadingLocation = false;
    } else {
      _resolveCurrentLocationAsOrigin();
    }
    // A re-plan already knows both ends: go straight to the alternatives.
    if (_origin != null && _destination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRoutes());
    }
  }

  @override
  void dispose() {
    // Drop the native annotation-manager handles; the overlay syncs are
    // guarded and no-op once these are null.
    _pins = null;
    _lines = null;
    super.dispose();
  }

  Future<void> _resolveCurrentLocationAsOrigin() async {
    try {
      final cached = await Geolocator.getLastKnownPosition();
      // A cached fix can be hours old; don't call that "Current location".
      final fresh =
          cached != null &&
          DateTime.now().difference(cached.timestamp) <
              const Duration(minutes: 5);
      final position = fresh
          ? cached
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                timeLimit: kLocationFixTimeout,
              ),
            );
      if (!mounted) return;
      setState(() {
        _origin = Geo.pos(position.latitude, position.longitude);
        _originName = 'Current location';
        _loadingLocation = false;
      });
      if (_destination != null) unawaited(_fetchRoutes());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingLocation = false;
      });
    }
  }

  Future<void> _pickOrigin() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) =>
            PickLocationScreen(title: 'Pick origin', initialCenter: _origin),
      ),
    );
    if (picked == null) return;
    _fetchToken++;
    setState(() {
      _origin = picked.position;
      _originName = picked.name;
      _routes = const [];
      _fetchingRoutes = false;
      _error = null;
    });
    _frameOn(picked.position);
  }

  Future<void> _pickDestination() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          title: 'Pick destination',
          initialCenter: _destination ?? _origin,
        ),
      ),
    );
    if (picked == null) return;
    _fetchToken++;
    setState(() {
      _destination = picked.position;
      _destinationName = picked.name;
      _routes = const [];
      _fetchingRoutes = false;
      _error = null;
    });
    _frameOn(picked.position);
  }

  void _frameOn(Position center) {
    unawaited(_mapKey.currentState?.flyTo(center, zoom: 10));
  }

  Future<void> _fetchRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    // Same place both ends: there is no route to find.
    if ((origin.lat - destination.lat).abs() < 1e-5 &&
        (origin.lng - destination.lng).abs() < 1e-5) {
      setState(() {
        _routes = const [];
        _error = 'Origin and destination are the same place.';
      });
      return;
    }

    final token = ++_fetchToken;
    setState(() {
      _fetchingRoutes = true;
      _error = null;
      _routes = const [];
    });
    try {
      final routes = await GoogleMapsApiService.directions(
        origin: origin,
        destination: destination,
      );
      if (!mounted || token != _fetchToken) return;
      setState(() {
        _routes = routes;
        _selectedRoute = 0;
      });
    } catch (e) {
      if (!mounted || token != _fetchToken) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && token == _fetchToken) {
        setState(() => _fetchingRoutes = false);
      }
    }
  }

  Future<void> _onStyleReady(MapboxMap map) async {
    _pins = await map.annotations.createPointAnnotationManager();
    _lines = await map.annotations.createPolylineAnnotationManager();
    _renderedPinKey = null;
    _renderedRouteKey = null;
    if (mounted) setState(() {});
  }

  void _confirm() {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null || _routes.isEmpty) return;
    final chosen = _routes[_selectedRoute];
    Navigator.of(context).pop(
      PlannedRoute(
        originName: _originName ?? 'Origin',
        originPoint: LatLngPoint(origin.lat.toDouble(), origin.lng.toDouble()),
        destinationName: _destinationName ?? 'Destination',
        destinationPoint: LatLngPoint(
          destination.lat.toDouble(),
          destination.lng.toDouble(),
        ),
        routePolyline: chosen.encodedPolyline,
      ),
    );
  }

  Future<void> _syncOverlays(double devicePixelRatio) async {
    final pins = _pins;
    final lines = _lines;
    if (pins == null || lines == null) return;

    final origin = _origin;
    final destination = _destination;
    // Read colors before any await.
    final nav = NavColors.of(context);
    final originColor = nav.foreground;
    final destinationColor = nav.activeRoute;
    final altColor = nav.altRoute.withValues(alpha: 0.6);

    final pinKey = '$origin|$destination';
    if (_renderedPinKey != pinKey) {
      _renderedPinKey = pinKey;
      _originPin ??= await MapMarkers.pin(
        originColor,
        Icons.trip_origin,
        devicePixelRatio: devicePixelRatio,
      );
      _destinationPin ??= await MapMarkers.pin(
        destinationColor,
        Icons.place_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      await pins.deleteAll();
      final options = <PointAnnotationOptions>[
        if (origin != null)
          PointAnnotationOptions(
            geometry: Point(coordinates: origin),
            image: _originPin,
            iconAnchor: IconAnchor.BOTTOM,
          ),
        if (destination != null)
          PointAnnotationOptions(
            geometry: Point(coordinates: destination),
            image: _destinationPin,
            iconAnchor: IconAnchor.BOTTOM,
          ),
      ];
      if (options.isNotEmpty) await pins.createMulti(options);
    }

    // Re-render whenever the route list is replaced or the selection changes.
    final routeKey = '${identityHashCode(_routes)}:$_selectedRoute';
    if (_renderedRouteKey != routeKey) {
      _renderedRouteKey = routeKey;
      await lines.deleteAll();
      if (_routes.length > 1) {
        await lines.createMulti([
          for (var i = 0; i < _routes.length; i++)
            if (_routes[i].points.length >= 2)
              PolylineAnnotationOptions(
                geometry: Geo.lineString(_routes[i].points),
                lineColor: i == _selectedRoute
                    ? destinationColor.toARGB32()
                    : altColor.toARGB32(),
                lineWidth: i == _selectedRoute ? 5 : 3,
                lineJoin: LineJoin.ROUND,
              ),
        ]);
      } else if (_routes.length == 1 && _routes.first.points.length >= 2) {
        await lines.create(
          PolylineAnnotationOptions(
            geometry: Geo.lineString(_routes.first.points),
            lineColor: destinationColor.toARGB32(),
            lineWidth: 5,
            lineJoin: LineJoin.ROUND,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: widget.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: _loadingLocation
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
                  child: BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        BrandListRow(
                          icon: Icons.trip_origin,
                          iconColor: BrandColors.primary,
                          title: _origin == null
                              ? 'Set origin'
                              : (_originName ?? 'Origin set'),
                          trailing: BrandSecondaryButton(
                            label: 'Pick',
                            expand: false,
                            onPressed: _pickOrigin,
                          ),
                        ),
                        const BrandRowDivider(),
                        BrandListRow(
                          icon: Icons.location_pin,
                          iconColor: BrandColors.primary,
                          title: _destination == null
                              ? 'Set destination'
                              : (_destinationName ?? 'Destination set'),
                          trailing: BrandSecondaryButton(
                            label: 'Pick',
                            expand: false,
                            onPressed: _pickDestination,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_origin != null && _destination != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BrandSpace.sm),
                    child: BrandPrimaryButton(
                      label: _fetchingRoutes
                          ? 'Finding routes…'
                          : 'Find routes',
                      leadingIcon: Icons.alt_route_rounded,
                      onPressed: _fetchingRoutes ? null : _fetchRoutes,
                      loading: _fetchingRoutes,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BrandSpace.sm),
                    child: BrandAlert(message: _error!),
                  ),
                if (_origin != null && _destination != null)
                  Expanded(
                    child: _RoutePreview(
                      mapKey: _mapKey,
                      center: _origin!,
                      onStyleReady: _onStyleReady,
                      onMapBuilt: () => unawaited(
                        _syncOverlays(MediaQuery.devicePixelRatioOf(context)),
                      ),
                    ),
                  ),
                if (_routes.isNotEmpty) ...[
                  const SizedBox(height: BrandSpace.sm),
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _routes.length; i++) ...[
                          if (i > 0) const BrandRowDivider(),
                          BrandListRow(
                            icon: i == _selectedRoute
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            iconColor: i == _selectedRoute
                                ? BrandColors.primary
                                : BrandColors.textMuted,
                            showChevron: false,
                            title: _routes[i].summary,
                            subtitle:
                                '${_routes[i].distanceLabel} · ${_routes[i].durationLabel}',
                            onTap: () => setState(() => _selectedRoute = i),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  BrandPrimaryButton(
                    label: 'Use this route',
                    onPressed: _confirm,
                  ),
                ],
              ],
            ),
    );
  }
}

/// The route-preview map. Kept as its own widget so the parent's frequent
/// rebuilds (chip selection, fetch state) don't recreate the map's camera.
class _RoutePreview extends StatelessWidget {
  const _RoutePreview({
    required this.mapKey,
    required this.center,
    required this.onStyleReady,
    required this.onMapBuilt,
  });

  final GlobalKey<RanmapMapViewState> mapKey;
  final Position center;
  final ValueChanged<MapboxMap> onStyleReady;
  final VoidCallback onMapBuilt;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onMapBuilt());
    return RanmapMapView(
      key: mapKey,
      center: center,
      zoom: 10,
      pitch: 0,
      onStyleReady: onStyleReady,
    );
  }
}
