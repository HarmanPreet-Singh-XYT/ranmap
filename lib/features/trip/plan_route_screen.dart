import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/constants/defaults.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
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
  const PlanRouteScreen({super.key});

  @override
  State<PlanRouteScreen> createState() => _PlanRouteScreenState();
}

class _PlanRouteScreenState extends State<PlanRouteScreen> {
  final _mapKey = GlobalKey<RanmapMapViewState>();

  Position? _origin;
  Position? _destination;
  List<RouteOption> _routes = const [];
  int _selectedRoute = 0;
  bool _loadingLocation = true;
  bool _fetchingRoutes = false;
  String? _error;

  PointAnnotationManager? _pins;
  PolylineAnnotationManager? _lines;
  Uint8List? _originPin;
  Uint8List? _destinationPin;
  String? _renderedPinKey;
  String? _renderedRouteKey;

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocationAsOrigin();
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
      final position =
          await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(timeLimit: kLocationFixTimeout),
              );
      if (!mounted) return;
      setState(() {
        _origin = Geo.pos(position.latitude, position.longitude);
        _loadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingLocation = false;
      });
    }
  }

  Future<void> _pickOrigin() async {
    final picked = await Navigator.of(context).push<Position>(
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          title: 'Pick origin',
          initialCenter: _origin,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _origin = picked);
    _frameOn(picked);
  }

  Future<void> _pickDestination() async {
    final picked = await Navigator.of(context).push<Position>(
      MaterialPageRoute(
        builder: (_) => PickLocationScreen(
          title: 'Pick destination',
          initialCenter: _destination ?? _origin,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _destination = picked);
    _frameOn(picked);
  }

  void _frameOn(Position center) {
    unawaited(_mapKey.currentState?.flyTo(center, zoom: 10));
  }

  Future<void> _fetchRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;

    setState(() {
      _fetchingRoutes = true;
      _error = null;
      _routes = const [];
    });
    try {
      final routes = await GoogleMapsApiService.directions(origin: origin, destination: destination);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _selectedRoute = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _fetchingRoutes = false);
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
    Navigator.of(context).pop(PlannedRoute(
      originName: 'Origin',
      originPoint: LatLngPoint(origin.lat.toDouble(), origin.lng.toDouble()),
      destinationName: 'Destination',
      destinationPoint: LatLngPoint(destination.lat.toDouble(), destination.lng.toDouble()),
      routePolyline: chosen.encodedPolyline,
    ));
  }

  Future<void> _syncOverlays(double devicePixelRatio) async {
    final pins = _pins;
    final lines = _lines;
    if (pins == null || lines == null) return;

    final origin = _origin;
    final destination = _destination;

    final pinKey = '$origin|$destination';
    if (_renderedPinKey != pinKey) {
      _renderedPinKey = pinKey;
      _originPin ??= await MapMarkers.pin(
        AppTheme.success, Icons.trip_origin, devicePixelRatio: devicePixelRatio);
      _destinationPin ??= await MapMarkers.pin(
        AppTheme.primary, Icons.place_rounded, devicePixelRatio: devicePixelRatio);
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
                    ? AppTheme.primary.toARGB32()
                    : Colors.grey.withValues(alpha: 0.5).toARGB32(),
                lineWidth: i == _selectedRoute ? 5 : 3,
                lineJoin: LineJoin.ROUND,
              ),
        ]);
      } else if (_routes.length == 1 && _routes.first.points.length >= 2) {
        await lines.create(PolylineAnnotationOptions(
          geometry: Geo.lineString(_routes.first.points),
          lineColor: AppTheme.primary.toARGB32(),
          lineWidth: 5,
          lineJoin: LineJoin.ROUND,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan route')),
      body: _loadingLocation
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.trip_origin, color: AppTheme.success),
                        title: Text(_origin == null ? 'Set origin' : 'Origin set'),
                        trailing: TextButton(onPressed: _pickOrigin, child: const Text('Pick')),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_pin, color: AppTheme.primary),
                        title: Text(_destination == null ? 'Set destination' : 'Destination set'),
                        trailing: TextButton(onPressed: _pickDestination, child: const Text('Pick')),
                      ),
                      if (_origin != null && _destination != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _fetchingRoutes ? null : _fetchRoutes,
                            icon: _fetchingRoutes
                                ? const SizedBox(
                                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.alt_route_rounded),
                            label: Text(_fetchingRoutes ? 'Finding routes…' : 'Find routes'),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                      ],
                    ],
                  ),
                ),
                if (_origin != null && _destination != null)
                  Expanded(
                    child: _RoutePreview(
                      mapKey: _mapKey,
                      center: _origin!,
                      onStyleReady: _onStyleReady,
                      onMapBuilt: () => unawaited(_syncOverlays(
                        MediaQuery.devicePixelRatioOf(context),
                      )),
                    ),
                  ),
                if (_routes.isNotEmpty) ...[
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _routes.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final route = _routes[i];
                        final selected = i == _selectedRoute;
                        return ChoiceChip(
                          selected: selected,
                          onSelected: (_) => setState(() => _selectedRoute = i),
                          label: SizedBox(
                            width: 140,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(route.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text('${route.distanceLabel} · ${route.durationLabel}'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(onPressed: _confirm, child: const Text('Use this route')),
                      ),
                    ),
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
