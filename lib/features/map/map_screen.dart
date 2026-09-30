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
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/nav_surface.dart';
import '../../data/models/group.dart';
import '../../data/models/map_post.dart';
import '../../data/models/route_option.dart';
import '../../data/models/saved_place.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/google_maps_api_service.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../social/social_providers.dart';
import '../trip/new_trip_screen.dart';
import '../trip/trip_providers.dart';
import 'add_map_post_screen.dart';
import 'group_convoy_screen.dart';
import 'live_sync_providers.dart';
import 'map_engine/map_engine.dart';
import 'map_post_providers.dart';
import 'map_post_viewer_sheet.dart';
import 'nearby_places_sheet.dart';
import 'navigate_to_member_sheet.dart';
import 'offline_maps_screen.dart';
import 'saved_place_providers.dart';
import 'saved_places_screen.dart';

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
  final _beam = HeadlightBeam();

  /// TEMPORARY, for testing: draw the headlight beam even when stationary.
  /// Set to false to hide it below walking pace.
  static const bool _alwaysShowBeam = true;

  PointAnnotationManager? _photoPoints;
  PointAnnotationManager? _placePoints;
  PointAnnotationManager? _savedPlacePoints;
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
  Uint8List? _savedPlacePin;

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
    // it there (or turning the location service back on) doesn't leave the user
    // stuck on the denied view.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(locationPermissionProvider);
      ref.invalidate(locationServiceEnabledProvider);
    }
  }

  // Guards so overlays are only rebuilt when their data actually changes.
  List<String>? _renderedSavedPlaceIds;
  List<String>? _renderedPostIds;
  String? _renderedRoutePolyline;
  String? _renderedPlaceId;

  // Set once after an overlay sync fails, so the user isn't left wondering why
  // a pin/route never appeared (a repeated failure doesn't spam toasts).
  bool _overlaySyncErrorShown = false;

  /// Surfaces a persistently-failing overlay sync instead of swallowing it: the
  /// user gets one notice rather than an overlay that silently never renders.
  void _reportOverlaySyncFailure(String what, Object error) {
    if (_overlaySyncErrorShown || !mounted) return;
    _overlaySyncErrorShown = true;
    showAppToast(
      context,
      "Some map details couldn't be shown. Reopen the map to try again.",
      error: true,
    );
  }

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
    _savedPlacePoints = null;
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
    _beam.reset();
    _postByAnnotationId.clear();
    _renderedPostIds = null;
    _renderedSavedPlaceIds = null;
    _renderedRoutePolyline = null;
    _renderedPlaceId = null;

    final photoPoints = await map.annotations.createPointAnnotationManager();
    final routeLines = await map.annotations.createPolylineAnnotationManager();
    final savedPlacePoints = await map.annotations
        .createPointAnnotationManager();
    if (generation != _styleGeneration || !mounted) return;

    _photoTapCancel = photoPoints.tapEvents(onTap: _onPhotoTap);
    setState(() {
      _photoPoints = photoPoints;
      _routeLines = routeLines;
      _savedPlacePoints = savedPlacePoints;
    });
  }

  void _onPhotoTap(PointAnnotation annotation) {
    final post = _postByAnnotationId[annotation.id];
    if (post != null) showMapPostViewerSheet(context, post);
  }

  Future<void> _setStyle(RanmapMapStyle style) async {
    if (style == _style) return;
    setState(() => _style = style);
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

  /// The single "layers" entry point: basemap type, 3D/terrain detail, and the
  /// occasional map actions, kept off the landing screen until asked for.
  Future<void> _showMapOptions(double deviceLat, double deviceLng) {
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final c = NavColors.of(sheetContext);

          Widget sectionTitle(String text) => Padding(
            padding: const EdgeInsets.only(bottom: BrandSpace.sm),
            child: Text(
              text,
              style: BrandText.weight(
                BrandText.titleSm,
                700,
              ).copyWith(color: BrandColors.textHeadline),
            ),
          );

          Widget styleTile(RanmapMapStyle style) {
            final selected = style == _style;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  _setStyle(style);
                  setSheet(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? c.activeRoute : c.mutedForeground,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        style.icon,
                        color: selected ? c.activeRoute : c.foreground,
                      ),
                      const SizedBox(height: 4),
                      Text(style.label, style: BrandText.labelSm),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget toggleTile(
            IconData icon,
            String label,
            bool value,
            Future<void> Function() onToggle,
          ) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: value ? c.activeRoute : c.foreground),
              title: Text(label),
              trailing: Switch(
                value: value,
                onChanged: (_) {
                  onToggle();
                  setSheet(() {});
                },
              ),
            );
          }

          Widget actionTile(IconData icon, String label, VoidCallback onTap) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: c.foreground),
              title: Text(label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onTap();
              },
            );
          }

          // ForUI sheets have no Material ancestor; the ink/list/switch widgets
          // below need one.
          return Material(
            type: MaterialType.transparency,
            child: BrandSheetSurface(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('Map type'),
                    Row(
                      children: [
                        for (final style in RanmapMapStyle.values) ...[
                          styleTile(style),
                          if (style != RanmapMapStyle.values.last)
                            const SizedBox(width: BrandSpace.sm),
                        ],
                      ],
                    ),
                    const SizedBox(height: BrandSpace.lg),
                    sectionTitle('Map details'),
                    toggleTile(
                      Icons.apartment_rounded,
                      '3D buildings',
                      _threeD,
                      _toggleThreeD,
                    ),
                    toggleTile(
                      Icons.landscape_rounded,
                      'Terrain',
                      _terrain,
                      _toggleTerrain,
                    ),
                    const SizedBox(height: BrandSpace.sm),
                    actionTile(
                      Icons.bookmark_add_outlined,
                      'Save this place',
                      () => _savePlace(deviceLat, deviceLng),
                    ),
                    actionTile(
                      Icons.bookmarks_outlined,
                      'Saved places',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedPlacesScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      Icons.diversity_3_rounded,
                      'Live convoys',
                      _openConvoys,
                    ),
                    actionTile(
                      Icons.download_for_offline_outlined,
                      'Offline maps',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OfflineMapsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  /// The map's entry into the group-convoy loop: pick one of your groups and
  /// open its live-convoy screen. Previously the only way in was
  /// Profile → Convoy Groups → group → Live convoy, so the core "roll together"
  /// surface wasn't reachable from the map at all.
  Future<void> _openConvoys() async {
    final List<Group> groups;
    try {
      groups = await ref.read(myGroupsProvider.future);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    if (groups.isEmpty) {
      showAppToast(
        context,
        'No convoy groups yet — create one to roll together live.',
      );
      return;
    }
    final activeId = ref.read(convoyGroupIdProvider);
    final selected = await showFSheet<({String id, String name})>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              for (final (i, group) in groups.indexed) ...[
                if (i > 0) const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.diversity_3_rounded,
                  iconColor: BrandColors.primary,
                  title: group.name,
                  subtitle: 'Live convoy',
                  trailing: activeId == group.id
                      ? const BrandPill(label: 'Riding', bold: true)
                      : null,
                  onTap: () =>
                      Navigator.of(sheetContext)
                          .pop((id: group.id, name: group.name)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GroupConvoyScreen(groupId: selected.id, groupName: selected.name),
      ),
    );
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
        // GPS course of travel; only trusted while actually moving (below).
        position.heading,
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
    double deviceHeadingDegrees,
  ) {
    final here = Geo.pos(deviceLat, deviceLng);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // Keep the AsyncValue around (not just valueOrNull) so a failed live-sync
    // fetch is surfaced instead of silently rendering as "0 teammates". The
    // provider also owns this device's outgoing position sharing, so watching
    // it here — only while a trip is active — keeps that alive too.
    // Live source: an active trip takes precedence; otherwise, if the user has
    // joined a group convoy, that crew's live positions. Either way the
    // teammate layer below is identical — it only cares about positions keyed
    // by user id.
    final convoyGroupId = ref.watch(convoyGroupIdProvider);
    final liveGroupId = activeTrip == null ? convoyGroupId : null;
    final hasLiveScope = activeTrip != null || liveGroupId != null;

    final memberLocationsAsync = activeTrip != null
        ? ref.watch(tripLiveSyncProvider(activeTrip.id))
        : liveGroupId != null
        ? ref.watch(groupLiveSyncProvider(liveGroupId))
        : null;
    final memberLocations =
        memberLocationsAsync?.valueOrNull ?? const <String, MemberLocation>{};

    final memberProfiles = activeTrip != null
        ? ref.watch(tripMembersProvider(activeTrip.id)).valueOrNull ?? const []
        : liveGroupId != null
        ? ref.watch(groupMembersProvider(liveGroupId)).valueOrNull ?? const []
        : const <Map<String, dynamic>>[];
    final profileByUserId = {
      for (final m in memberProfiles)
        m['user_id'] as String: m['profiles'] as Map<String, dynamic>?,
    };
    final convoyGroupName = liveGroupId == null
        ? null
        : ref.watch(groupProvider(liveGroupId)).valueOrNull?.name;

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
    final shareLocation = ref.watch(
      appSettingsProvider.select((s) => s.shareLocation),
    );

    // Only show telemetry when the platform actually reported a speed:
    // geolocator returns a negative value (e.g. -1 on iOS) when it has none,
    // so anything below zero is treated as "no reading" and omitted. Zero is a
    // genuine stationary reading and is shown.
    final liveSpeedMps = deviceSpeedMps >= 0 ? deviceSpeedMps : null;

    final mapPostsAsync = activeTrip == null
        ? null
        : ref.watch(tripMapPostsProvider(activeTrip.id));
    final mapPosts = mapPostsAsync?.valueOrNull ?? const <MapPost>[];

    // The AI copilot's saved places are independent of any trip, so they're
    // fetched — and pinned — whether or not a convoy is active.
    final savedPlaces =
        ref.watch(savedPlacesProvider).valueOrNull ?? const <SavedPlace>[];

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
      // GPS course is meaningless below walking pace, so the beam hides then —
      // unless [_alwaysShowBeam] is on for testing, which shows it standing
      // still (pointing along the last known course, or north if there is none).
      final movingHeading = deviceSpeedMps > 1.0 ? deviceHeadingDegrees : null;
      unawaited(
        _beam.sync(
          map,
          lat: deviceLat,
          lng: deviceLng,
          headingDegrees:
              movingHeading ??
              (_alwaysShowBeam
                  ? (deviceHeadingDegrees >= 0 ? deviceHeadingDegrees : 0)
                  : null),
          colorArgb: BrandColors.primary.toARGB32(),
          // Standard/Satellite draw custom layers under the basemap unless slotted.
          slot: _style.isStandard ? 'top' : null,
        ),
      );
      unawaited(_syncPhotoPins(mapPosts, devicePixelRatio));
      unawaited(_syncSavedPlacePins(savedPlaces, devicePixelRatio));
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
            onCameraChanged: (data) {
              final map = _mapKey.currentState?.map;
              if (map != null) {
                unawaited(_beam.onCameraChanged(map, data.cameraState.zoom));
              }
            },
          ),
          if (liveError != null)
            Positioned(
              top: 16 + topInset,
              left: 16,
              child: _LiveSyncErrorChip(
                detail: friendlyError(liveError),
                onRetry: () {
                  if (activeTripId != null) {
                    ref.invalidate(tripLiveSyncProvider(activeTripId));
                    ref.invalidate(tripMapPostsProvider(activeTripId));
                  } else if (liveGroupId != null) {
                    ref.invalidate(groupLiveSyncProvider(liveGroupId));
                  }
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
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    badgeCount:
                        ref.watch(unreadNotificationsProvider).valueOrNull ?? 0,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                      ref.invalidate(unreadNotificationsProvider);
                    },
                  ),
                  _MapControl(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Recenter on me',
                    onTap: () =>
                        _mapKey.currentState?.flyTo(here, zoom: kFollowZoom),
                  ),
                  _MapControl(
                    icon: Icons.layers_rounded,
                    tooltip: 'Map options',
                    onTap: () => _showMapOptions(deviceLat, deviceLng),
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
                  if (activeTrip != null || liveGroupId != null)
                    _MapControl(
                      icon: shareLocation
                          ? Icons.share_location_rounded
                          : Icons.location_disabled_rounded,
                      tooltip: shareLocation
                          ? 'Pause location sharing'
                          : 'Resume location sharing',
                      active: shareLocation,
                      onTap: () => ref
                          .read(appSettingsProvider.notifier)
                          .setShareLocation(!shareLocation),
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
                            color: (!hasLiveScope || !shareLocation)
                                ? BrandColors.textMuted
                                : BrandColors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          !hasLiveScope
                              ? 'No active convoy'
                              : shareLocation
                              ? 'Convoy live · ${memberLocations.length}'
                              : 'Location sharing paused',
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
                  if (!hasLiveScope)
                    _buildGetStartedCard(
                      context,
                      deviceLat,
                      deviceLng,
                      unit,
                      savedPlaces,
                    )
                  else
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
                                  activeTrip?.title ??
                                      convoyGroupName ??
                                      'Your crew',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: BrandText.weight(
                                    BrandText.titleSm,
                                    700,
                                  ).copyWith(color: BrandColors.textHeadline),
                                ),
                                Text(
                                  '${memberLocations.length} teammate${memberLocations.length == 1 ? '' : 's'} live now',
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

  /// Shown in the map's bottom card when there's no active convoy. The map is
  /// the landing tab, so with nothing live it still has to say what to do next
  /// rather than sit empty. When the user has AI-saved places, their real list
  /// is surfaced here so the map doesn't read as empty.
  Widget _buildGetStartedCard(
    BuildContext context,
    double deviceLat,
    double deviceLng,
    DistanceUnit unit,
    List<SavedPlace> savedPlaces,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: BrandColors.secondaryFixed.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_rounded,
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
                    'No convoy yet',
                    style: BrandText.weight(
                      BrandText.titleSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  Text(
                    'Plan a trip and your crew rolls together — live location, voice and shared stops.',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: BrandSpace.md),
        // The copilot's real saved places, when there are any. With none, the
        // card renders exactly as the plain empty state it's always been.
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: BrandSpace.md),
          _SavedPlacesList(
            places: savedPlaces,
            deviceLat: deviceLat,
            deviceLng: deviceLng,
            unit: unit,
            onTap: _flyToSavedPlace,
          ),
        ],
        const SizedBox(height: BrandSpace.md),
        BrandPrimaryButton(
          label: 'Plan your first trip',
          leadingIcon: Icons.add_rounded,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const NewTripScreen())),
        ),
      ],
    );
  }

  /// Moves the camera to a saved place's stored coordinates. A place without
  /// coordinates has nothing to fly to, so it's a no-op (and its card row is
  /// left non-tappable).
  void _flyToSavedPlace(SavedPlace place) {
    final point = place.point;
    if (point == null) return;
    unawaited(
      _mapKey.currentState?.flyTo(
        Geo.pos(point.lat, point.lng),
        zoom: kPlaceZoom,
      ),
    );
  }

  /// Saves the device's current location as a named bookmark, independent of
  /// any trip. It then appears as a pin and in the no-convoy card below.
  Future<void> _savePlace(double lat, double lng) async {
    final name = await showAppTextDialog(
      context,
      title: 'Save this place',
      label: 'Name',
      hint: 'Great viewpoint',
      confirmLabel: 'Save',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Name');
    if (validationError != null) {
      if (mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref
          .read(savedPlaceRepositoryProvider)
          .createPlace(name: name, lat: lat, lng: lng);
      ref.invalidate(savedPlacesProvider);
      if (mounted) showAppToast(context, 'Saved "$name".');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Renders the user's saved places as bookmark pins, reusing the same marker
  /// plumbing (and change-guard) as [MapMarkers.pin] photo pins. Places with no
  /// stored coordinates can't be pinned and are skipped silently.
  Future<void> _syncSavedPlacePins(
    List<SavedPlace> places,
    double devicePixelRatio,
  ) async {
    final manager = _savedPlacePoints;
    if (manager == null) return;
    final located = [
      for (final place in places)
        if (place.hasLocation) place,
    ];
    final ids = [for (final place in located) place.id];
    if (listEquals(ids, _renderedSavedPlaceIds)) return;

    try {
      _savedPlacePin ??= await MapMarkers.pin(
        BrandColors.primary,
        Icons.bookmark_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      final image = _savedPlacePin!;

      await manager.deleteAll();
      if (located.isNotEmpty) {
        await manager.createMulti([
          for (final place in located)
            PointAnnotationOptions(
              geometry: Geo.point(place.point!.lat, place.point!.lng),
              image: image,
              iconAnchor: IconAnchor.BOTTOM,
            ),
        ]);
      }
      // Commit the guard only after the work succeeded, so a failure is retried
      // on the next rebuild instead of being permanently suppressed.
      _renderedSavedPlaceIds = ids;
    } catch (error) {
      // A failed overlay sync must not take the map down — but don't hide it.
      _reportOverlaySyncFailure('saved-place pins', error);
    }
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
    } catch (error) {
      // A failed overlay sync must not take the map down — but don't hide it.
      _reportOverlaySyncFailure('photo pins', error);
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
    } catch (error) {
      _reportOverlaySyncFailure('route line', error);
    }
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
    } catch (error) {
      _reportOverlaySyncFailure('selected place', error);
    }
  }

  Future<void> _showTeammates(List<_Teammate> teammates) async {
    final c = NavColors.of(context);
    final selected = await showFSheet<_Teammate>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        padding: const EdgeInsets.only(top: BrandSpace.md),
        child: ListView(
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
    // `false` here means the device's location *service* is off — a different
    // fix (device settings) than a denied app permission.
    final serviceOff =
        ref.watch(locationServiceEnabledProvider).valueOrNull == false;
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
                serviceOff
                    ? 'Location services are off. Turn them on so Ranmap can '
                          'show you on the map and keep your trip in sync with '
                          'your group.'
                    : 'Ranmap needs your location to show you on the map and keep '
                          'your trip in sync with your group.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.foreground, fontSize: 16),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FButton(
                  size: .lg,
                  onPress: () {
                    if (serviceOff) {
                      // The device's location settings, not the app's — that's
                      // where the service toggle lives.
                      unawaited(Geolocator.openLocationSettings());
                    } else {
                      // Re-request first: if permission was only denied once,
                      // this prompts again instead of sending to Settings.
                      ref.invalidate(locationServiceEnabledProvider);
                      ref.invalidate(locationPermissionProvider);
                    }
                  },
                  child: Text(
                    serviceOff ? 'Turn on location' : 'Allow location',
                  ),
                ),
              ),
              if (!serviceOff) ...[
                const SizedBox(height: 6),
                FButton(
                  variant: .ghost,
                  onPress: () => Geolocator.openAppSettings(),
                  child: const Text('Open settings'),
                ),
              ],
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
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Null for plain actions; true/false for toggles.
  final bool? active;

  /// A count badge over the icon (e.g. unread notifications); hidden when 0.
  final int badgeCount;

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
          child: Center(
            child: Badge(
              isLabelVisible: badgeCount > 0,
              label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
              backgroundColor: BrandColors.error,
              child: Icon(icon, size: 23, color: color),
            ),
          ),
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

/// The AI copilot's saved places, rendered as a compact real list in the
/// no-convoy card: a heading and one row per place (name + distance). Kept
/// short so the card stays a card; the rest are summarised with a real count.
class _SavedPlacesList extends StatelessWidget {
  const _SavedPlacesList({
    required this.places,
    required this.deviceLat,
    required this.deviceLng,
    required this.unit,
    required this.onTap,
  });

  final List<SavedPlace> places;
  final double deviceLat;
  final double deviceLng;
  final DistanceUnit unit;
  final ValueChanged<SavedPlace> onTap;

  /// How many rows to show before collapsing the remainder into a count — the
  /// card must not grow with the user's saved-places backlog.
  static const _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final shown = places.take(_maxRows).toList();
    final hidden = places.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bookmark_rounded, size: 14, color: BrandColors.primary),
            const SizedBox(width: 6),
            Text(
              'Saved places',
              style: BrandText.weight(
                BrandText.labelSm,
                700,
              ).copyWith(color: BrandColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: BrandSpace.xs),
        for (final place in shown)
          _SavedPlaceRow(
            place: place,
            deviceLat: deviceLat,
            deviceLng: deviceLng,
            unit: unit,
            // Only a place with real coordinates has somewhere to fly to;
            // a name-only place stays a plainly non-tappable row.
            onTap: place.hasLocation ? () => onTap(place) : null,
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: BrandSpace.xs),
            child: Text(
              '+$hidden more',
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// One saved place in the card: a bookmark pod, the place name and how far away
/// it is from the device. Tapping flies the map camera to it.
class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({
    required this.place,
    required this.deviceLat,
    required this.deviceLng,
    required this.unit,
    required this.onTap,
  });

  final SavedPlace place;
  final double deviceLat;
  final double deviceLng;
  final DistanceUnit unit;

  /// Null when the place has no stored coordinates, leaving the row inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final point = place.point;
    final distanceLabel = point == null
        ? 'No location saved'
        : formatShortDistance(
            haversineMeters(deviceLat, deviceLng, point.lat, point.lng),
            unit,
          );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              height: 30,
              width: 30,
              decoration: BoxDecoration(
                color: BrandColors.secondaryFixed.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bookmark_rounded,
                size: 16,
                color: BrandColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.labelLg.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  Text(
                    distanceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.my_location_rounded,
                size: 18,
                color: BrandColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
