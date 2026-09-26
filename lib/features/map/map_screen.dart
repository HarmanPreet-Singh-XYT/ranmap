import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Position` is geolocator's own type; the map engine exports the GeoJSON
// `Position`, so hide geolocator's to avoid the collision.
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/constants/avatars.dart';
import '../../core/constants/defaults.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/util/units.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/nav_surface.dart';
import '../../data/models/map_post.dart';
import '../../data/models/route_option.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stop.dart';
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
typedef _Teammate = ({
  String userId,
  String? username,
  String avatarId,
  double lat,
  double lng,
});

/// Initial great-circle bearing (radians, clockwise from true north) from
/// (`lat1`,`lng1`) to (`lat2`,`lng2`) — the standard "initial bearing" formula.
/// Fed to [Transform.rotate] so a teammate's arrow genuinely points at them;
/// nothing here is hard-coded.
double _initialBearingRadians(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
  return math.atan2(y, x);
}

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

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
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
  late RanmapMapStyle _style;
  late bool _threeD;
  late bool _terrain;

  Uint8List? _photoPin;
  Uint8List? _placePin;

  /// Bumped on every style load so a slow load can discard its work if another
  /// load started (or the screen went away) meanwhile.
  int _styleGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Map defaults come from Settings; changes there are applied live below.
    final settings = ref.read(appSettingsProvider);
    _style = RanmapMapStyle.fromId(settings.mapStyleId);
    _threeD = settings.mapThreeD;
    _terrain = settings.mapTerrain;
  }

  /// Mirrors a Settings change onto the live map (avoids a rebuild loop by
  /// only acting when the value actually differs).
  void _applySettings(AppSettings settings) {
    final style = RanmapMapStyle.fromId(settings.mapStyleId);
    final mapState = _mapKey.currentState;
    if (style != _style) {
      setState(() => _style = style);
      unawaited(mapState?.setStyle(style));
    }
    if (settings.mapThreeD != _threeD) {
      setState(() => _threeD = settings.mapThreeD);
      unawaited(mapState?.setBuildings(settings.mapThreeD));
    }
    if (settings.mapTerrain != _terrain) {
      setState(() => _terrain = settings.mapTerrain);
      unawaited(mapState?.setTerrain(settings.mapTerrain));
    }
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
    ref.read(appSettingsProvider.notifier).setMapStyleId(_style.name);
    await _mapKey.currentState?.setStyle(_style);
  }

  Future<void> _toggleThreeD() async {
    setState(() => _threeD = !_threeD);
    ref.read(appSettingsProvider.notifier).setMapThreeD(_threeD);
    await _mapKey.currentState?.setBuildings(_threeD);
  }

  Future<void> _toggleTerrain() async {
    setState(() => _terrain = !_terrain);
    ref.read(appSettingsProvider.notifier).setMapTerrain(_terrain);
    await _mapKey.currentState?.setTerrain(_terrain);
  }

  Future<void> _searchNearby(Position center) async {
    // Offer "search along the route" when the active trip has a planned route.
    final polyline = ref.read(activeTripProvider).valueOrNull?.routePolyline;
    final place = await showNearbyPlacesSheet(
      context,
      center: center,
      routePolyline: (polyline == null || polyline.isEmpty) ? null : polyline,
    );
    if (place == null || !mounted) return;
    setState(() => _selectedPlace = place);
    await _mapKey.currentState?.flyTo(place.location, zoom: kPlaceZoom);
  }

  @override
  Widget build(BuildContext context) {
    // Apply Settings changes (map style / 3D / terrain) to the live map.
    ref.listen(appSettingsProvider, (_, next) => _applySettings(next));
    final permissionAsync = ref.watch(locationPermissionProvider);

    return permissionAsync.when(
      data: (granted) =>
          granted ? _buildLocationView(context) : const _LocationDeniedView(),
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) =>
          _LocationErrorView(detail: friendlyError(e), onRetry: _retryLocation),
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
      data: (position) => _buildMap(
        context,
        position.latitude,
        position.longitude,
        activeTrip,
        // Geolocator's own speed in m/s (negative when it has no reading).
        position.speed,
      ),
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) =>
          _LocationErrorView(detail: friendlyError(e), onRetry: _retryLocation),
    );
  }

  /// The mode of the leg currently in progress, if any: the leg arriving at the
  /// first stop the traveller hasn't reached yet. The trip origin is reached
  /// once the trip is active, so the first stop's leg is the origin → first
  /// stop segment. The leg is matched by the stop it arrives at (`to_stop_id`),
  /// so the lookup survives a reorder/delete rather than relying on `seq`.
  /// Returns null when the trip isn't active, every stop has arrived, or no leg
  /// was recorded for the next stop — the caller then falls back to the profile
  /// vehicle.
  String? _activeLegMode(Trip? trip, List<TripStop> stops, List<TripLeg> legs) {
    if (trip == null || trip.status != TripStatus.active) return null;
    TripStop? nextStop;
    for (final stop in stops) {
      if (stop.actualArrival == null) {
        nextStop = stop;
        break;
      }
    }
    if (nextStop == null) return null;
    for (final leg in legs) {
      if (leg.toStopId == nextStop.id) return leg.mode;
    }
    return null;
  }

  Widget _buildMap(
    BuildContext context,
    double deviceLat,
    double deviceLng,
    Trip? activeTrip,
    double deviceSpeedMps,
  ) {
    final here = Geo.pos(deviceLat, deviceLng);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // Keep the AsyncValue around (not just valueOrNull) so a failed live-sync
    // fetch is surfaced instead of silently rendering as "0 teammates".
    final memberLocationsAsync = activeTrip == null
        ? null
        : ref.watch(tripMemberLocationsProvider(activeTrip.id));
    final memberLocations =
        memberLocationsAsync?.valueOrNull ?? const <String, MemberLocation>{};

    final memberProfiles = activeTrip == null
        ? const <Map<String, dynamic>>[]
        : ref.watch(tripMembersProvider(activeTrip.id)).valueOrNull ?? const [];
    final profileByUserId = {
      for (final m in memberProfiles)
        m['user_id'] as String: m['profiles'] as Map<String, dynamic>?,
    };

    final teammates = <_Teammate>[];
    final poses = <VehiclePose>[];
    // Real safe-gap figure: the great-circle distance to the closest teammate,
    // recomputed from the live positions (null when nobody else is on the trip).
    double? nearestTeammateMeters;
    for (final entry in memberLocations.entries) {
      final loc = entry.value;
      final profile = profileByUserId[entry.key];
      final username = profile?['username'] as String?;
      final vehicleType =
          profile?['vehicle_type'] as String? ?? kDefaultVehicleType;
      teammates.add((
        userId: entry.key,
        username: username,
        avatarId: profile?['avatar_id'] as String? ?? kDefaultAvatarSeed,
        lat: loc.lat,
        lng: loc.lng,
      ));
      poses.add(
        VehiclePose(
          id: entry.key,
          vehicleType: vehicleType,
          lat: loc.lat,
          lng: loc.lng,
          heading: loc.heading,
        ),
      );
      final meters = haversineMeters(deviceLat, deviceLng, loc.lat, loc.lng);
      if (nearestTeammateMeters == null || meters < nearestTeammateMeters) {
        nearestTeammateMeters = meters;
      }
    }

    final profileVehicleType =
        ref.watch(myProfileProvider).valueOrNull?.vehicleType ??
        kDefaultVehicleType;
    // While a leg is in progress, the traveller's own 3D model matches that
    // leg's mode; otherwise it falls back to their profile vehicle.
    final tripStops = activeTrip == null
        ? const <TripStop>[]
        : ref.watch(tripStopsProvider(activeTrip.id)).valueOrNull ??
              const <TripStop>[];
    final tripLegs = activeTrip == null
        ? const <TripLeg>[]
        : ref.watch(tripLegsProvider(activeTrip.id)).valueOrNull ??
              const <TripLeg>[];
    final userVehicleType =
        _activeLegMode(activeTrip, tripStops, tripLegs) ?? profileVehicleType;
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    // Only show telemetry when the platform actually reported a speed:
    // geolocator returns a negative value (e.g. -1 on iOS) when it has none,
    // so anything below zero is treated as "no reading" and omitted. Zero is a
    // genuine stationary reading and is shown.
    final liveSpeedMps = deviceSpeedMps >= 0 ? deviceSpeedMps : null;

    final mapPostsAsync = activeTrip == null
        ? null
        : ref.watch(tripMapPostsProvider(activeTrip.id));
    final mapPosts = mapPostsAsync?.valueOrNull ?? const <MapPost>[];

    // The overlay is decorative — the map still works if it fails — but the
    // user should know it's stale rather than assume nobody is on the trip.
    final liveError = memberLocationsAsync?.error ?? mapPostsAsync?.error;
    final activeTripId = activeTrip?.id;

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

    // The map is full-bleed (under the status bar), but its floating overlays
    // must clear a notch/status bar — FScaffold has no header here to inset them.
    final topInset = MediaQuery.paddingOf(context).top;

    return FScaffold(
      childPad: false,
      child: Stack(
        children: [
          RanmapMapView(
            key: _mapKey,
            center: here,
            zoom: kFollowZoom,
            style: _style,
            threeD: _threeD,
            terrain: _terrain,
            showUserLocation: true,
            userVehicleType: userVehicleType,
            onStyleReady: _onStyleReady,
          ),
          if (activeTripId != null && liveError != null)
            Positioned(
              top: 16 + topInset,
              left: 16,
              child: _LiveSyncErrorChip(
                detail: friendlyError(liveError),
                onRetry: () {
                  ref.invalidate(tripMemberLocationsProvider(activeTripId));
                  ref.invalidate(tripMapPostsProvider(activeTripId));
                },
              ),
            ),
          Positioned(
            top: 16 + topInset,
            right: 16,
            child: FloatingPanel(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapControl(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Recenter on me',
                    onTap: () =>
                        _mapKey.currentState?.flyTo(here, zoom: kFollowZoom),
                  ),
                  _MapControl(
                    icon: _style.icon,
                    tooltip: _style.label,
                    onTap: _cycleStyle,
                  ),
                  _MapControl(
                    icon: _threeD
                        ? Icons.apartment_rounded
                        : Icons.location_city_outlined,
                    tooltip: _threeD
                        ? 'Hide 3D buildings'
                        : 'Show 3D buildings',
                    onTap: _toggleThreeD,
                    active: _threeD,
                  ),
                  _MapControl(
                    icon: _terrain
                        ? Icons.landscape_rounded
                        : Icons.landscape_outlined,
                    tooltip: _terrain ? 'Hide terrain' : 'Show terrain',
                    onTap: _toggleTerrain,
                    active: _terrain,
                  ),
                  _MapControl(
                    icon: Icons.search_rounded,
                    tooltip: 'Search nearby places',
                    onTap: () => _searchNearby(here),
                  ),
                  if (activeTrip != null)
                    _MapControl(
                      icon: Icons.add_a_photo_outlined,
                      tooltip: 'Add a photo to the map',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddMapPostScreen(
                            tripId: activeTrip.id,
                            lat: deviceLat,
                            lng: deviceLng,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Live-convoy status pill, centred just below the status bar.
          Positioned(
            top: 8 + topInset,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: BrandColors.surface.withValues(alpha: 0.92),
                      borderRadius: BrandRadii.pill,
                      boxShadow: BrandShadows.subtle,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 8,
                          width: 8,
                          decoration: BoxDecoration(
                            color: activeTrip == null
                                ? BrandColors.textMuted
                                : BrandColors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activeTrip == null
                              ? 'No active convoy'
                              : 'Convoy live · ${memberLocations.length}',
                          style: BrandText.labelSm.copyWith(
                            color: BrandColors.textHeadline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Own live speed, straight from the device's Position — shown
                  // only when the platform actually reported one.
                  if (liveSpeedMps != null) ...[
                    const SizedBox(width: BrandSpace.sm),
                    BrandPill(
                      label: formatSpeed(liveSpeedMps * 3.6, unit),
                      icon: Icons.speed_rounded,
                      background: BrandColors.surface.withValues(alpha: 0.92),
                      foreground: BrandColors.textHeadline,
                      iconColor: BrandColors.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: BrandCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live roster: each teammate's avatar + how far away they are,
                  // tap to navigate to them.
                  if (teammates.isNotEmpty) ...[
                    SizedBox(
                      height: 68,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: teammates.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: BrandSpace.md),
                        itemBuilder: (context, i) {
                          final teammate = teammates[i];
                          return _TeammateChip(
                            teammate: teammate,
                            meters: haversineMeters(
                              deviceLat,
                              deviceLng,
                              teammate.lat,
                              teammate.lng,
                            ),
                            // Real initial bearing so the arrow points at them.
                            bearing: _initialBearingRadians(
                              deviceLat,
                              deviceLng,
                              teammate.lat,
                              teammate.lng,
                            ),
                            unit: unit,
                            onTap: () => showNavigateToMemberSheet(
                              context,
                              destination: Geo.pos(teammate.lat, teammate.lng),
                              username: teammate.username,
                              vehicleType: profileVehicleType,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: BrandSpace.sm),
                    // Safe-gap readout: the live distance to the closest
                    // teammate, recomputed from real positions above.
                    if (nearestTeammateMeters != null)
                      Row(
                        children: [
                          Icon(
                            Icons.social_distance_rounded,
                            size: 14,
                            color: BrandColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Nearest: ${formatShortDistance(nearestTeammateMeters, unit).replaceAll(' away', '')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BrandText.bodySm.copyWith(
                                color: BrandColors.textBody,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: BrandSpace.sm),
                  ],
                  GestureDetector(
                    onTap: teammates.isEmpty
                        ? null
                        : () => _showTeammates(teammates),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: BrandColors.secondaryFixed.withValues(
                              alpha: 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            color: BrandColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeTrip == null
                                    ? 'No active trip'
                                    : activeTrip.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BrandText.weight(
                                  BrandText.titleSm,
                                  700,
                                ).copyWith(color: BrandColors.textHeadline),
                              ),
                              Text(
                                activeTrip == null
                                    ? 'Start a trip to roll together'
                                    : '${memberLocations.length} teammate${memberLocations.length == 1 ? '' : 's'} live now',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BrandText.bodySm.copyWith(
                                  color: BrandColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (teammates.isNotEmpty)
                          Icon(
                            Icons.chevron_right_rounded,
                            color: BrandColors.textMuted,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncPhotoPins(
    List<MapPost> posts,
    double devicePixelRatio,
  ) async {
    final manager = _photoPoints;
    if (manager == null) return;
    final ids = [for (final post in posts) post.id];
    if (listEquals(ids, _renderedPostIds)) return;

    try {
      _photoPin ??= await MapMarkers.pin(
        NavColors.of(context).highway,
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
    final lineColor = NavColors.of(context).activeRoute.toARGB32();

    try {
      await manager.deleteAll();
      if (encodedPolyline != null) {
        final points = _routePoints(encodedPolyline);
        if (points.length >= 2) {
          await manager.create(
            PolylineAnnotationOptions(
              geometry: Geo.lineString(points),
              lineColor: lineColor,
              lineWidth: 4,
              lineJoin: LineJoin.ROUND,
            ),
          );
        }
      }
      _renderedRoutePolyline = encodedPolyline;
    } catch (_) {}
  }

  Future<void> _syncSelectedPlace(double devicePixelRatio) async {
    final place = _selectedPlace;
    if (_renderedPlaceId == place?.placeId) return;
    if (_mapKey.currentState?.map == null) return;
    final pinColor = NavColors.of(context).activeRoute;

    try {
      // The place pin lives on its own manager so it isn't wiped out every time
      // the photo set changes.
      _placePoints ??= await _mapKey.currentState?.map?.annotations
          .createPointAnnotationManager();
      final placeManager = _placePoints;
      if (placeManager == null) return;

      _placePin ??= await MapMarkers.pin(
        pinColor,
        Icons.place_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      final image = _placePin!;

      await placeManager.deleteAll();
      if (place != null) {
        await placeManager.create(
          PointAnnotationOptions(
            geometry: Point(coordinates: place.location),
            image: image,
            iconAnchor: IconAnchor.BOTTOM,
          ),
        );
      }
      _renderedPlaceId = place?.placeId;
    } catch (_) {}
  }

  Future<void> _showTeammates(List<_Teammate> teammates) async {
    final c = NavColors.of(context);
    final selected = await showFSheet<_Teammate>(
      context: context,
      side: FLayout.btt,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Live teammates',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          FTileGroup(
            children: [
              for (final teammate in teammates)
                FTile(
                  prefix: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      color: c.activeRoute,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    teammate.username != null
                        ? '@${teammate.username}'
                        : 'Teammate',
                  ),
                  suffix: const Icon(Icons.navigation_rounded),
                  onPress: () => Navigator.of(context).pop(teammate),
                ),
            ],
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await showNavigateToMemberSheet(
      context,
      destination: Geo.pos(selected.lat, selected.lng),
      username: selected.username,
      vehicleType: ref.read(myProfileProvider).valueOrNull?.vehicleType,
    );
  }
}

class _LocationDeniedView extends ConsumerWidget {
  const _LocationDeniedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    return FScaffold(
      childPad: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded, size: 56, color: c.activeRoute),
              const SizedBox(height: 20),
              Text(
                'Ranmap needs your location to show you on the map and keep '
                'your trip in sync with your group.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.foreground, fontSize: 16),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                // Re-request first: if permission was only denied once, this
                // prompts again instead of sending the user to Settings.
                child: FButton(
                  size: .lg,
                  onPress: () => ref.invalidate(locationPermissionProvider),
                  child: const Text('Allow location'),
                ),
              ),
              const SizedBox(height: 6),
              FButton(
                variant: .ghost,
                onPress: () => Geolocator.openAppSettings(),
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
    final c = NavColors.of(context);
    return FScaffold(
      childPad: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not get your location. Make sure location services and '
                'permission are enabled.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.foreground, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground),
              ),
              const SizedBox(height: 20),
              FButton(onPress: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

/// One live teammate in the map's convoy roster: avatar, handle and how far
/// away they are. Tapping navigates to them.
class _TeammateChip extends StatelessWidget {
  const _TeammateChip({
    required this.teammate,
    required this.meters,
    required this.bearing,
    required this.unit,
    required this.onTap,
  });

  final _Teammate teammate;
  final double meters;

  /// Initial bearing to the teammate, in radians clockwise from north — the
  /// angle the arrow is rotated by so it physically points at them.
  final double bearing;
  final DistanceUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarView(
              seed: teammate.avatarId,
              size: 36,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(height: 4),
            Text(
              teammate.username != null ? '@${teammate.username}' : 'Teammate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.labelSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // North-up glyph rotated by the live bearing to this teammate.
                Transform.rotate(
                  angle: bearing,
                  child: Icon(
                    Icons.navigation_rounded,
                    size: 12,
                    color: BrandColors.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    formatShortDistance(meters, unit).replaceAll(' away', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single glanceable control in the map's floating control panel.
class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Null for plain actions; true/false for toggles.
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final color = switch (active) {
      true => c.activeRoute,
      false => c.mutedForeground,
      null => c.foreground,
    };

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, size: 23, color: color),
        ),
      ),
    );
  }
}

/// Small non-blocking banner shown over the map when the live teammate/photo
/// overlay fails to load, so a broken connection isn't mistaken for an empty
/// trip. Explicit retry re-fetches both overlay providers.
class _LiveSyncErrorChip extends StatelessWidget {
  const _LiveSyncErrorChip({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return FloatingPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: detail,
            child: Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: c.destructive,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              "Live teammates aren't updating",
              style: TextStyle(color: c.foreground, fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          FButton(
            variant: .outline,
            size: .xs,
            onPress: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
