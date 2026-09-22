import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Position` is geolocator's own type; the map engine exports the GeoJSON
// `Position`, so hide geolocator's to avoid the collision.
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/router/auth_state_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/map_post.dart';
import '../../data/models/route_option.dart';
import '../../data/models/trip.dart';
import '../../data/services/google_maps_api_service.dart';
import '../trip/trip_providers.dart';
import 'add_map_post_screen.dart';
import 'live_sync_providers.dart';
import 'map_engine/map_engine.dart';
import 'map_post_providers.dart';
import 'map_post_viewer_sheet.dart';
import 'nearby_places_sheet.dart';
import 'navigate_to_member_sheet.dart';

/// A teammate shown in the live-teammates sheet.
typedef _Teammate = ({String userId, String? username, double lat, double lng});

/// Live map showing the current user's position (as a 3D vehicle puck),
/// teammates' vehicles as 3D models on the active trip, photos pinned to the
/// route, and the active trip route.
///
/// Migrated from `google_maps_flutter` to the Mapbox Maps SDK for a real 3D
/// layer: Mapbox Standard's extruded buildings/trees/landmarks, terrain, and
/// per-vehicle glTF models (see `map_engine/`). Teammate markers are no longer
/// directly tappable — Mapbox Standard doesn't support `queryRenderedFeatures`,
/// and the vehicles are style layers rather than annotations — so tapping the
/// status card opens a list of teammates to navigate to instead.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with WidgetsBindingObserver {
  final _mapKey = GlobalKey<RanmapMapViewState>();
  final _vehicles = VehicleModelLayerManager();

  PointAnnotationManager? _photoPoints;
  PointAnnotationManager? _placePoints;
  PolylineAnnotationManager? _routeLines;
  Cancelable? _photoTapCancel;

  /// Maps a created annotation back to its post for tap handling (annotation
  /// ids are assigned by the SDK, so this is the reliable link).
  final Map<String, MapPost> _postByAnnotationId = {};

  NearbyPlace? _selectedPlace;
  RanmapMapStyle _style = RanmapMapStyle.standard;
  bool _threeD = true;
  bool _terrain = true;

  Uint8List? _photoPin;
  Uint8List? _placePin;

  /// Bumped on every style load so a slow load can discard its work if another
  /// load started (or the screen went away) meanwhile.
  int _styleGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Release the native annotation managers; the style syncs are all
    // internally guarded so they simply no-op once these are null.
    unawaited(_disposeAnnotationManagers());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check location permission when returning from Settings, so granting
    // it there doesn't leave the user stuck on the denied view.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(locationPermissionProvider);
    }
  }

  // Guards so overlays are only rebuilt when their data actually changes.
  List<String>? _renderedPostIds;
  String? _renderedRoutePolyline;
  String? _renderedPlaceId;

  // Decoding the route polyline on every build is wasteful for a long route,
  // so cache the result keyed by the encoded string.
  String? _decodedRouteSource;
  List<Position> _decodedRoute = const [];

  List<Position> _routePoints(String encoded) {
    if (_decodedRouteSource != encoded) {
      _decodedRouteSource = encoded;
      _decodedRoute = GoogleMapsApiService.decodePolyline(encoded);
    }
    return _decodedRoute;
  }

  /// Disposes the annotation managers (and their tap subscriptions). Their
  /// sources/layers vanish with the style anyway.
  Future<void> _disposeAnnotationManagers() async {
    _photoTapCancel?.cancel();
    _photoTapCancel = null;
    _photoPoints = null;
    _placePoints = null;
    _routeLines = null;
  }

  Future<void> _onStyleReady(MapboxMap map) async {
    final generation = ++_styleGeneration;

    // Null the managers *synchronously* first, so any rebuild that fires while
    // this async load is in flight sees them as absent and skips its overlay
    // sync (otherwise it would run against a manager the reload just dropped
    // and commit its change-guard, leaving the overlay permanently missing).
    await _disposeAnnotationManagers();
    _vehicles.reset();
    _postByAnnotationId.clear();
    _renderedPostIds = null;
    _renderedRoutePolyline = null;
    _renderedPlaceId = null;

    final photoPoints = await map.annotations.createPointAnnotationManager();
    final routeLines = await map.annotations.createPolylineAnnotationManager();
    if (generation != _styleGeneration || !mounted) return;

    _photoTapCancel = photoPoints.tapEvents(onTap: _onPhotoTap);
    setState(() {
      _photoPoints = photoPoints;
      _routeLines = routeLines;
    });
  }

  void _onPhotoTap(PointAnnotation annotation) {
    final post = _postByAnnotationId[annotation.id];
    if (post != null) showMapPostViewerSheet(context, post);
  }

  Future<void> _cycleStyle() async {
    setState(() => _style = _style.next);
    await _mapKey.currentState?.setStyle(_style);
  }

  Future<void> _toggleThreeD() async {
    setState(() => _threeD = !_threeD);
    await _mapKey.currentState?.setBuildings(_threeD);
  }

  Future<void> _toggleTerrain() async {
    setState(() => _terrain = !_terrain);
    await _mapKey.currentState?.setTerrain(_terrain);
  }

  Future<void> _searchNearby(Position center) async {
    final place = await showNearbyPlacesSheet(context, center: center);
    if (place == null || !mounted) return;
    setState(() => _selectedPlace = place);
    await _mapKey.currentState?.flyTo(place.location, zoom: 16);
  }

  @override
  Widget build(BuildContext context) {
    final permissionAsync = ref.watch(locationPermissionProvider);

    return permissionAsync.when(
      data: (granted) =>
          granted ? _buildLocationView(context) : const _LocationDeniedView(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _LocationErrorView(detail: friendlyError(e), onRetry: _retryLocation),
    );
  }

  void _retryLocation() {
    ref.invalidate(locationPermissionProvider);
    ref.invalidate(devicePositionProvider);
  }

  Widget _buildLocationView(BuildContext context) {
    // Keep the location broadcast alive while this screen is mounted and a
    // trip is active; it's a no-op provider when there's no active trip. Only
    // watched once permission is granted, so the GPS stream never errors.
    ref.watch(locationBroadcastProvider);

    final activeTrip = ref.watch(activeTripProvider).valueOrNull;
    final positionAsync = ref.watch(devicePositionProvider);

    return positionAsync.when(
      data: (position) =>
          _buildMap(context, position.latitude, position.longitude, activeTrip),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _LocationErrorView(detail: friendlyError(e), onRetry: _retryLocation),
    );
  }

  Widget _buildMap(BuildContext context, double deviceLat, double deviceLng, Trip? activeTrip) {
    final here = Geo.pos(deviceLat, deviceLng);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    final memberLocations = activeTrip == null
        ? const <String, MemberLocation>{}
        : ref.watch(tripMemberLocationsProvider(activeTrip.id)).valueOrNull ?? {};

    final memberProfiles = activeTrip == null
        ? const <Map<String, dynamic>>[]
        : ref.watch(tripMembersProvider(activeTrip.id)).valueOrNull ?? const [];
    final profileByUserId = {
      for (final m in memberProfiles)
        m['user_id'] as String: m['profiles'] as Map<String, dynamic>?,
    };

    final teammates = <_Teammate>[];
    final poses = <VehiclePose>[];
    for (final entry in memberLocations.entries) {
      final loc = entry.value;
      final profile = profileByUserId[entry.key];
      final username = profile?['username'] as String?;
      final vehicleType = profile?['vehicle_type'] as String? ?? 'car';
      teammates.add((userId: entry.key, username: username, lat: loc.lat, lng: loc.lng));
      poses.add(VehiclePose(
        id: entry.key,
        vehicleType: vehicleType,
        lat: loc.lat,
        lng: loc.lng,
        heading: loc.heading,
      ));
    }

    final myVehicleType = ref.watch(myProfileProvider).valueOrNull?.vehicleType ?? 'car';

    final mapPosts = activeTrip == null
        ? const <MapPost>[]
        : ref.watch(tripMapPostsProvider(activeTrip.id)).valueOrNull ?? const <MapPost>[];

    final routePolyline = activeTrip?.routePolyline;

    // Fire-and-forget: each of these diffs against what's already on the map,
    // so on a rebuild where nothing changed they do nothing.
    final map = _mapKey.currentState?.map;
    if (map != null) {
      unawaited(_vehicles.sync(map, poses));
      unawaited(_syncPhotoPins(mapPosts, devicePixelRatio));
      unawaited(_syncRoute(routePolyline));
      unawaited(_syncSelectedPlace(devicePixelRatio));
    }

    return Scaffold(
      body: Stack(
        children: [
          RanmapMapView(
            key: _mapKey,
            center: here,
            zoom: 15.5,
            style: _style,
            threeD: _threeD,
            terrain: _terrain,
            showUserLocation: true,
            userVehicleType: myVehicleType,
            onStyleReady: _onStyleReady,
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  onPressed: () => _mapKey.currentState?.flyTo(here, zoom: 15.5),
                  tooltip: 'Recenter on me',
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'mapStyle',
                  onPressed: _cycleStyle,
                  tooltip: _style.label,
                  child: Icon(_style.icon),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'threeD',
                  onPressed: _toggleThreeD,
                  tooltip: _threeD ? 'Hide 3D buildings' : 'Show 3D buildings',
                  child: Icon(_threeD ? Icons.apartment_rounded : Icons.location_city_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'terrain',
                  onPressed: _toggleTerrain,
                  tooltip: _terrain ? 'Hide terrain' : 'Show terrain',
                  child: Icon(_terrain ? Icons.landscape_rounded : Icons.landscape_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'nearby',
                  onPressed: () => _searchNearby(here),
                  tooltip: 'Search nearby places',
                  child: const Icon(Icons.search_rounded),
                ),
                if (activeTrip != null) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'addPhoto',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddMapPostScreen(
                          tripId: activeTrip.id,
                          lat: deviceLat,
                          lng: deviceLng,
                        ),
                      ),
                    ),
                    tooltip: 'Add a photo to the map',
                    child: const Icon(Icons.add_a_photo_outlined),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 56,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: teammates.isEmpty ? null : () => _showTeammates(teammates),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_filled_rounded, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          activeTrip == null
                              ? 'No active trip'
                              : '${activeTrip.title} · ${memberLocations.length} teammate${memberLocations.length == 1 ? '' : 's'} live',
                        ),
                      ),
                      if (teammates.isNotEmpty) const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncPhotoPins(List<MapPost> posts, double devicePixelRatio) async {
    final manager = _photoPoints;
    if (manager == null) return;
    final ids = [for (final post in posts) post.id];
    if (listEquals(ids, _renderedPostIds)) return;

    try {
      _photoPin ??= await MapMarkers.pin(
        const Color(0xFFF5B301),
        Icons.photo_camera_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      final image = _photoPin!;

      await manager.deleteAll();
      _postByAnnotationId.clear();
      if (posts.isNotEmpty) {
        final created = await manager.createMulti([
          for (final post in posts)
            PointAnnotationOptions(
              geometry: Geo.point(post.lat, post.lng),
              image: image,
              iconAnchor: IconAnchor.BOTTOM,
            ),
        ]);
        // `createMulti` preserves the input order, so the returned annotations
        // line up index-for-index with `posts`.
        for (var i = 0; i < created.length && i < posts.length; i++) {
          final annotation = created[i];
          if (annotation != null) _postByAnnotationId[annotation.id] = posts[i];
        }
      }
      // Commit the guard only after the work succeeded, so a failure is retried
      // on the next rebuild instead of being permanently suppressed.
      _renderedPostIds = ids;
    } catch (_) {
      // A failed overlay sync must not take the map down.
    }
  }

  Future<void> _syncRoute(String? encodedPolyline) async {
    final manager = _routeLines;
    if (manager == null) return;
    if (_renderedRoutePolyline == encodedPolyline) return;

    try {
      await manager.deleteAll();
      if (encodedPolyline != null) {
        final points = _routePoints(encodedPolyline);
        if (points.length >= 2) {
          await manager.create(PolylineAnnotationOptions(
            geometry: Geo.lineString(points),
            lineColor: AppTheme.primary.toARGB32(),
            lineWidth: 4,
            lineJoin: LineJoin.ROUND,
          ));
        }
      }
      _renderedRoutePolyline = encodedPolyline;
    } catch (_) {}
  }

  Future<void> _syncSelectedPlace(double devicePixelRatio) async {
    final place = _selectedPlace;
    if (_renderedPlaceId == place?.placeId) return;
    if (_mapKey.currentState?.map == null) return;

    try {
      // The place pin lives on its own manager so it isn't wiped out every time
      // the photo set changes.
      _placePoints ??= await _mapKey.currentState?.map?.annotations.createPointAnnotationManager();
      final placeManager = _placePoints;
      if (placeManager == null) return;

      _placePin ??= await MapMarkers.pin(
        const Color(0xFF8E44AD),
        Icons.place_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      final image = _placePin!;

      await placeManager.deleteAll();
      if (place != null) {
        await placeManager.create(PointAnnotationOptions(
          geometry: Point(coordinates: place.location),
          image: image,
          iconAnchor: IconAnchor.BOTTOM,
        ));
      }
      _renderedPlaceId = place?.placeId;
    } catch (_) {}
  }

  Future<void> _showTeammates(List<_Teammate> teammates) async {
    final selected = await showModalBottomSheet<_Teammate>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Live teammates', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final teammate in teammates)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE5DC),
                  child: Icon(Icons.directions_car_filled_rounded, color: AppTheme.primary),
                ),
                title: Text(teammate.username != null ? '@${teammate.username}' : 'Teammate'),
                trailing: const Icon(Icons.navigation_rounded),
                onTap: () => Navigator.of(context).pop(teammate),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await showNavigateToMemberSheet(
      context,
      destination: Geo.pos(selected.lat, selected.lng),
      username: selected.username,
    );
  }
}

class _LocationDeniedView extends ConsumerWidget {
  const _LocationDeniedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_rounded, size: 48, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Ranmap needs your location to show you on the map and keep '
                'your trip in sync with your group.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Re-request first: if permission was only denied once, this
              // prompts again instead of sending the user to Settings.
              FilledButton(
                onPressed: () => ref.invalidate(locationPermissionProvider),
                child: const Text('Allow location'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Geolocator.openAppSettings(),
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  const _LocationErrorView({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not get your location. Make sure location services and '
                'permission are enabled.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
