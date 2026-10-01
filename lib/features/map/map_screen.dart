import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Position` is geolocator's own type; the map engine exports the GeoJSON
// `Position`, so hide geolocator's to avoid the collision.
import 'package:geolocator/geolocator.dart' hide Position;

import '../../core/constants/avatars.dart';
import '../../core/constants/defaults.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/feedback/app_feedback.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/util/units.dart';
import '../../core/util/validation.dart';
import '../../core/providers/app_prefs_provider.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/nav_surface.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import '../../data/models/map_post.dart';
import '../../data/models/route_option.dart';
import '../../data/models/saved_place.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/google_maps_api_service.dart';
import '../chat/chat_share.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../social/social_providers.dart';
import '../trip/new_trip_screen.dart';
import '../trip/plan_route_screen.dart' show PlannedRoute;
import '../trip/trip_providers.dart';
import '../trip/trip_recap_screen.dart';
import 'add_map_post_screen.dart';
import 'group_convoy_screen.dart';
import 'live_sync_providers.dart';
import 'map_engine/compass.dart';
import 'map_engine/map_engine.dart';
import 'map_post_providers.dart';
import 'map_post_viewer_sheet.dart';
import 'nearby_places_sheet.dart';
import 'navigate_to_member_sheet.dart';
import 'offline_maps_screen.dart';
import 'place_details_sheet.dart';
import 'map_navigation.dart';
import 'navigation/nav_engine.dart';
import 'navigation/nav_widgets.dart';
import 'pick_location_screen.dart';
import 'saved_place_providers.dart';
import 'saved_places_screen.dart';

/// A teammate shown in the live-teammates sheet.
typedef _Teammate = ({
  String userId,
  String? username,
  String avatarId,
  String vehicleType,
  double lat,
  double lng,
});

/// Photos within this distance of each other share one map pin (with a count).
const double _photoStackRadiusMeters = 10;

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

  /// The teammate the camera is locked onto, or null. Released by dragging the
  /// map, recentring on yourself, or the teammate dropping off the live feed.
  String? _followingUserId;

  // --- turn-by-turn navigation ---------------------------------------------
  NavEngine? _navEngine;
  NavProgress? _nav;
  bool _navFollow = true;
  bool _rerouting = false;
  int _offRouteFixes = 0;
  DateTime? _lastReroute;
  (double, double)? _navLastFix;
  int? _announcedStep; // next-maneuver index already chimed at ~180 m
  int? _closeStep; // ...and at ~40 m

  /// Latest own position and trip destination, captured in build so navigation
  /// requests (which arrive outside build) can route from where you are now.
  double? _deviceLat;
  double? _deviceLng;
  NearbyPlace? _navDestination;

  /// When the member-target route was last (re)fetched, to throttle refreshes
  /// as the teammate moves.
  DateTime? _memberRouteAt;
  (double, double)? _followLast;

  /// The most recent GPS course (degrees) seen while moving.
  double? _lastCourse;

  /// The phone's compass heading (degrees), which the puck and the headlight
  /// beam follow — so the beam turns as you turn, like Google Maps' cone.
  double? _compass;
  StreamSubscription<double>? _compassSub;

  /// TEMPORARY, for testing: draw the headlight beam even when stationary.
  /// Set to false to hide it below walking pace.
  static const bool _alwaysShowBeam = true;

  PointAnnotationManager? _photoPoints;
  PointAnnotationManager? _placePoints;
  PointAnnotationManager? _savedPlacePoints;

  /// Avatar pins floating over each live teammate's vehicle.
  PointAnnotationManager? _teammatePoints;
  Cancelable? _teammateTapCancel;
  final Map<String, PointAnnotation> _teammateAnnotations = {};
  final Map<String, String> _userByAnnotationId = {};
  final Map<String, (double, double)> _teammateLast = {};
  String? _renderedTeammateKey;
  List<_Teammate> _latestTeammates = const [];
  bool _teammateSyncBusy = false;
  bool _teammateSyncQueued = false;
  final _routeRenderer = RouteLines();

  /// Directions preview for [_selectedPlace]: candidate routes from the user's
  /// position, the chosen one drawn highlighted (others muted).
  List<RouteOption> _previewRoutes = const [];
  int _previewIndex = 0;
  bool _previewLoading = false;
  String? _previewError;

  /// Bumped whenever the preview is cancelled or the place changes, so a slow
  /// directions response for a stale request is dropped.
  int _previewToken = 0;
  Cancelable? _photoTapCancel;

  /// Maps a created annotation back to its post for tap handling (annotation
  /// ids are assigned by the SDK, so this is the reliable link).
  /// Photos behind each map pin. Posts at (nearly) the same spot share one pin.
  final Map<String, List<MapPost>> _postByAnnotationId = {};

  NearbyPlace? _selectedPlace;
  late RanmapMapStyle _style;
  late bool _threeD;
  late bool _terrain;

  Uint8List? _placePin;
  Uint8List? _savedPlacePin;

  /// Bumped on every style load so a slow load can discard its work if another
  /// load started (or the screen went away) meanwhile.
  int _styleGeneration = 0;

  /// Annotation managers the native map still owns. A native call on a manager
  /// the SDK already dropped (a style reload, the map view being rebuilt) throws
  /// on the platform thread and kills the app — Dart's try/catch can't intercept
  /// it — so every call is gated on [_live] immediately beforehand.
  final Set<PointAnnotationManager> _liveManagers = {};

  bool _live(PointAnnotationManager? manager) =>
      manager != null && mounted && _liveManagers.contains(manager);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A request raised before the map tab existed (e.g. from a chat message).
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeNavRequest());
    // Map defaults come from Settings; changes there are applied live below.
    final settings = ref.read(appSettingsProvider);
    _style = RanmapMapStyle.fromId(settings.mapStyleId);
    _threeD = settings.mapThreeD;
    _terrain = settings.mapTerrain;
    _listenToCompass();
  }

  void _listenToCompass() {
    // Empty on devices with no magnetometer; the beam then falls back to GPS
    // course. Events arrive many times a second, so only act on real turns.
    _compassSub = RanmapCompass.headings.listen((heading) {
      if (!heading.isFinite) return;
      final normalized = (heading % 360 + 360) % 360;
      final previous = _compass;
      if (previous != null) {
        final delta = ((normalized - previous + 540) % 360) - 180;
        if (delta.abs() < 3) return;
      }
      _compass = normalized;
      final map = _mapKey.currentState?.map;
      if (map != null) unawaited(_beam.updateHeading(map, normalized));
    });
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
    unawaited(_compassSub?.cancel());
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
    }
  }

  // Guards so overlays are only rebuilt when their data actually changes.
  List<String>? _renderedSavedPlaceIds;
  List<String>? _renderedPostIds;

  /// The manager those ids were drawn on. A style/map rebuild replaces the
  /// manager, so the guard must also key on its identity — otherwise a rebuild
  /// that produces the same post ids would skip the redraw and the pins would
  /// silently never come back.
  PointAnnotationManager? _renderedPostManager;
  String? _renderedPlaceId;

  // Set once after an overlay sync fails, so the user isn't left wondering why
  // a pin/route never appeared (a repeated failure doesn't spam toasts).
  bool _overlaySyncErrorShown = false;

  /// Surfaces a persistently-failing overlay sync instead of swallowing it: the
  /// user gets one notice rather than an overlay that silently never renders.
  void _reportOverlaySyncFailure(String what, Object error) {
    debugPrint('map overlay: $what sync failed: $error');
    if (_overlaySyncErrorShown || !mounted) return;
    _overlaySyncErrorShown = true;
    // These syncs are kicked off from build, so a synchronously-failing overlay
    // would otherwise call setState on the toaster mid-build and abort the
    // frame. Defer to after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppToast(
        context,
        "Some map details couldn't be shown. Reopen the map to try again.",
        error: true,
      );
    });
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
    _liveManagers.clear();
    _photoTapCancel?.cancel();
    _photoTapCancel = null;
    _photoPoints = null;
    _placePoints = null;
    _savedPlacePoints = null;
    _teammateTapCancel?.cancel();
    _teammateTapCancel = null;
    _teammatePoints = null;
    _teammateAnnotations.clear();
    _userByAnnotationId.clear();
    _teammateLast.clear();
    _renderedTeammateKey = null;
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
    _renderedPostManager = null;
    _renderedSavedPlaceIds = null;
    _routeRenderer.reset();
    _renderedPlaceId = null;

    final photoPoints = await map.annotations.createPointAnnotationManager();
    final savedPlacePoints = await map.annotations
        .createPointAnnotationManager();
    // Created last so teammate pins draw above the other markers.
    final teammatePoints = await map.annotations.createPointAnnotationManager();
    if (generation != _styleGeneration || !mounted) return;
    _liveManagers.addAll([photoPoints, savedPlacePoints, teammatePoints]);

    _photoTapCancel = photoPoints.tapEvents(onTap: _onPhotoTap);
    _teammateTapCancel = teammatePoints.tapEvents(onTap: _onTeammateTap);
    _addMapInteractions(map);
    setState(() {
      _photoPoints = photoPoints;
      _savedPlacePoints = savedPlacePoints;
      _teammatePoints = teammatePoints;
    });
  }

  void _onPhotoTap(PointAnnotation annotation) {
    final stack = _postByAnnotationId[annotation.id];
    if (stack != null && stack.isNotEmpty) {
      showMapPostViewerSheet(context, stack.first, stack: stack);
    }
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

  Future<void> _searchNearby(Position center, {String? type}) async {
    // Offer "search along the route" when the active trip has a planned route.
    final polyline = ref.read(activeTripProvider).valueOrNull?.routePolyline;
    final selection = await showNearbyPlacesSheet(
      context,
      center: center,
      routePolyline: (polyline == null || polyline.isEmpty) ? null : polyline,
      initialType: type,
    );
    if (selection == null || !mounted) return;
    await _selectPlace(selection.place);
    // The user asked for directions from the details sheet — start the in-app
    // route now (the card also offers a Directions button).
    if (selection.startDirections && mounted) {
      await _previewDirections(center.lat.toDouble(), center.lng.toDouble());
    }
  }

  /// Selects [place] (from the nearby list, a tapped POI, or a long-press) and
  /// shows its card with a Directions action.
  Future<void> _selectPlace(NearbyPlace place, {bool fly = true}) async {
    if (!mounted) return;
    _previewToken++;
    setState(() {
      _selectedPlace = place;
      _previewRoutes = const [];
      _previewIndex = 0;
      _previewLoading = false;
      _previewError = null;
    });
    if (fly) {
      await _mapKey.currentState?.flyTo(place.location, zoom: kPlaceZoom);
    }
  }

  void _clearSelectedPlace() {
    _previewToken++;
    setState(() {
      _selectedPlace = null;
      _previewRoutes = const [];
      _previewIndex = 0;
      _previewLoading = false;
      _previewError = null;
    });
  }

  /// Tap a point of interest, or long-press anywhere, to select it — like
  /// Google Maps. POI taps need the Standard style's `poi` featureset; the
  /// long-press works on every style.
  void _addMapInteractions(MapboxMap map) {
    const poiId = 'ranmap-poi-tap';
    const pinId = 'ranmap-long-tap';
    try {
      map.removeInteraction(poiId);
      map.removeInteraction(pinId);
    } catch (_) {}
    try {
      map.addInteraction(
        TapInteraction(StandardPOIs(), (feature, gesture) {
          Position location;
          try {
            location = feature.coordinate!.coordinates;
          } catch (_) {
            location = gesture.point.coordinates;
          }
          unawaited(
            _selectPlace(
              NearbyPlace(
                name: feature.name ?? 'Place',
                placeId: 'poi:${location.lat},${location.lng}',
                category: feature.category,
                location: location,
              ),
            ),
          );
        }),
        interactionID: poiId,
      );
    } catch (e) {
      // Styles without the Standard `poi` featureset can't tap POIs.
      debugPrint('POI tap interaction unavailable: $e');
    }
    try {
      // Tap a muted route line to make it the chosen one, like Google Maps.
      map.removeInteraction('ranmap-route-tap');
      map.addInteraction(
        TapInteraction.onMap(
          (gesture) => unawaited(_pickRouteAt(map, gesture.point.coordinates)),
          stopPropagation: false,
        ),
        interactionID: 'ranmap-route-tap',
      );
    } catch (e) {
      debugPrint('Route tap interaction unavailable: $e');
    }
    try {
      map.addInteraction(
        LongTapInteraction.onMap((gesture) {
          // A light buzz confirms the hold registered and the pin dropped.
          HapticFeedback.mediumImpact();
          final location = gesture.point.coordinates;
          unawaited(
            _selectPlace(
              NearbyPlace(
                name: 'Dropped pin',
                placeId: 'pin:${location.lat},${location.lng}',
                location: location,
              ),
            ),
          );
        }),
        interactionID: pinId,
      );
    } catch (e) {
      debugPrint('Long-press interaction unavailable: $e');
    }
  }

  /// Chooses the previewed route nearest to a map tap, if the tap landed close
  /// enough to one of the lines (within ~36 px).
  Future<void> _pickRouteAt(MapboxMap map, Position tap) async {
    if (_previewRoutes.length < 2 || !mounted) return;
    final zoom = (await map.getCameraState()).zoom;
    final lat = tap.lat.toDouble();
    final lng = tap.lng.toDouble();
    final metersPerPx =
        78271.517 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
    final tolerance = 36 * metersPerPx;

    var best = -1;
    var bestDistance = double.infinity;
    for (final (i, route) in _previewRoutes.indexed) {
      final d = _distanceToLineMeters(lat, lng, route.points);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (best >= 0 &&
        bestDistance <= tolerance &&
        best != _previewIndex &&
        mounted) {
      setState(() => _previewIndex = best);
    }
  }

  /// Shortest distance in metres from a point to a polyline (flat-earth
  /// approximation, plenty accurate at tap-tolerance scale).
  static double _distanceToLineMeters(
    double lat,
    double lng,
    List<Position> line,
  ) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = metersPerDegLat * math.cos(lat * math.pi / 180);
    double x(Position p) => (p.lng.toDouble() - lng) * metersPerDegLng;
    double y(Position p) => (p.lat.toDouble() - lat) * metersPerDegLat;

    var best = double.infinity;
    for (var i = 0; i < line.length - 1; i++) {
      final ax = x(line[i]);
      final ay = y(line[i]);
      final bx = x(line[i + 1]);
      final by = y(line[i + 1]);
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSq = dx * dx + dy * dy;
      final t = lengthSq == 0
          ? 0.0
          : ((-ax * dx - ay * dy) / lengthSq).clamp(0.0, 1.0);
      final px = ax + t * dx;
      final py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < best) best = d;
    }
    return best;
  }

  /// Drops the directions preview but keeps the place selected, so the user can
  /// back out of a route without losing the pin.
  void _cancelRoutePreview() {
    _previewToken++;
    setState(() {
      _previewRoutes = const [];
      _previewIndex = 0;
      _previewLoading = false;
      _previewError = null;
    });
  }

  /// Fetches routes from the user's position to the selected place and draws
  /// the best one highlighted on the map.
  Future<void> _previewDirections(
    double lat,
    double lng, {
    bool fit = true,
  }) async {
    final place = _selectedPlace;
    if (place == null || _previewLoading) return;

    // Already there: don't spend a routing call on a zero-length route.
    final meters = haversineMeters(
      lat,
      lng,
      place.location.lat.toDouble(),
      place.location.lng.toDouble(),
    );
    if (meters < 30) {
      setState(() => _previewError = "You're already at this spot.");
      return;
    }

    final token = ++_previewToken;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      const modes = {'car', 'bike', 'scooter', 'suv', 'other'};
      final vehicle = ref.read(myProfileProvider).valueOrNull?.vehicleType;
      final routes = await GoogleMapsApiService.directions(
        origin: Geo.pos(lat, lng),
        destination: place.location,
        profile: modes.contains(vehicle) ? vehicle : null,
        withSteps: true,
      );
      // Cancelled (or another place chosen) while the request was in flight.
      if (!mounted || token != _previewToken) return;
      setState(() {
        _previewRoutes = routes;
        _previewIndex = 0;
        // A teammate we're navigating to moved: follow the fresh route.
        if (_navEngine != null) {
          _navEngine = NavEngine(routes.first);
          _nav = _navEngine!.update(lat, lng);
        }
      });
      if (fit) unawaited(_fitRoute(routes.first.points));
    } catch (e) {
      if (mounted && token == _previewToken) {
        setState(() => _previewError = friendlyError(e));
      }
    } finally {
      if (mounted && token == _previewToken) {
        setState(() => _previewLoading = false);
      }
    }
  }

  /// Whether a selected place has something Google can resolve — a dropped pin
  /// or an unnamed POI would only spend a search on a garbage text query.
  bool _canShowDetails(NearbyPlace place) =>
      !place.placeId.startsWith('pin:') &&
      !_isNavTarget(place) &&
      place.name.isNotEmpty &&
      place.name != 'Place' &&
      place.name != 'Dropped pin';

  /// Opens the rich details sheet for a place already selected on the map
  /// (a tapped POI or dropped pin), routing to it if the user asks.
  Future<void> _openPlaceDetails(
    NearbyPlace place,
    double lat,
    double lng,
  ) async {
    if (!_canShowDetails(place)) return;
    final action = await showPlaceDetailsSheet(context, place);
    if (!mounted || action == null) return;
    if (action == PlaceDetailsAction.directions) {
      await _previewDirections(lat, lng);
    }
  }

  /// Switches which of several active trips the map follows.
  Future<void> _pickActiveTrip(List<Trip> trips, Trip? current) async {
    final picked = await showFSheet<Trip>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, trip) in trips.indexed) ...[
                if (i > 0) const BrandRowDivider(),
                BrandListRow(
                  icon: trip.id == current?.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  iconColor: BrandColors.primary,
                  title: trip.title,
                  subtitle: trip.destinationName == null
                      ? 'Live now'
                      : 'Live now · to ${trip.destinationName}',
                  showChevron: false,
                  onTap: () => Navigator.of(sheetContext).pop(trip),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(selectedMapTripIdProvider.notifier).state = picked.id;
    // Forget the previous trip's route line so the new one is drawn.
    _routeRenderer.reset();
    final target = picked.destinationPoint ?? picked.originPoint;
    if (target != null) {
      await _mapKey.currentState?.flyTo(
        Geo.pos(target.lat, target.lng),
        zoom: 12,
      );
    }
  }

  /// Attaches the previewed route to a trip the user picks (or starts a new
  /// trip from it), so the road becomes part of the trip instead of a one-off.
  Future<void> _useRouteForTrip(double lat, double lng) async {
    final place = _selectedPlace;
    if (place == null || _previewRoutes.isEmpty) return;
    final route = _previewRoutes[_previewIndex];

    final List<Trip> trips;
    try {
      trips = await ref.read(myTripsProvider.future);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final usable = [
      for (final t in trips)
        if (t.status == TripStatus.planned || t.status == TripStatus.active) t,
    ];
    if (!mounted) return;

    // null result = dismissed; a Trip with empty id = "new trip".
    final choice = await showFSheet<Trip?>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: SingleChildScrollView(
          child: BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandListRow(
                  icon: Icons.add_road_rounded,
                  iconColor: BrandColors.primary,
                  title: 'New trip with this route',
                  subtitle: 'To ${place.name}',
                  showChevron: false,
                  onTap: () =>
                      Navigator.of(sheetContext)
                          .pop(Trip.draft(createdBy: '', title: '')),
                ),
                for (final trip in usable) ...[
                  const BrandRowDivider(),
                  BrandListRow(
                    icon: trip.status == TripStatus.active
                        ? Icons.play_circle_outline_rounded
                        : Icons.event_outlined,
                    iconColor: BrandColors.primary,
                    title: trip.title,
                    subtitle: trip.status == TripStatus.active
                        ? 'Live now · replaces its route'
                        : 'Planned · replaces its route',
                    showChevron: false,
                    onTap: () => Navigator.of(sheetContext).pop(trip),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final origin = LatLngPoint(lat, lng);
    final destination = LatLngPoint(
      place.location.lat.toDouble(),
      place.location.lng.toDouble(),
    );

    if (choice.id.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NewTripScreen(
            initialTitle: 'Trip to ${place.name}',
            initialRoute: PlannedRoute(
              originName: 'Current location',
              originPoint: origin,
              destinationName: place.name,
              destinationPoint: destination,
              routePolyline: route.encodedPolyline,
            ),
          ),
        ),
      );
      if (mounted) _clearSelectedPlace();
      return;
    }

    try {
      final live = choice.status == TripStatus.active;
      await ref
          .read(tripRepositoryProvider)
          .updateRoute(
            tripId: choice.id,
            // A live trip keeps its original start; a planned one now starts
            // where this route starts.
            originName: live ? null : 'Current location',
            originPoint: live ? null : origin,
            destinationName: place.name,
            destinationPoint: destination,
            routePolyline: route.encodedPolyline,
          );
      refreshTripData(ref, tripId: choice.id);
      if (!mounted) return;
      showAppToast(context, 'Route set for "${choice.title}".');
      _clearSelectedPlace();
    } catch (e, stack) {
      // friendlyError hides details on purpose; keep the real cause in the log.
      debugPrint('Use route for trip failed: $e\n$stack');
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Frames [points] on screen, leaving room for the bottom card.
  Future<void> _fitRoute(List<Position> points) async {
    final map = _mapKey.currentState?.map;
    if (map == null || points.length < 2) return;
    final step = math.max(1, points.length ~/ 200);
    final sample = <Position>[
      for (var i = 0; i < points.length; i += step) points[i],
      points.last,
    ];
    try {
      final camera = await map.cameraForCoordinatesPadding(
        [for (final p in sample) Point(coordinates: p)],
        CameraOptions(),
        MbxEdgeInsets(top: 140, left: 48, bottom: 340, right: 96),
        null,
        null,
      );
      await map.flyTo(camera, MapAnimationOptions(duration: 900));
    } catch (_) {}
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
    ref.listen(mapNavRequestProvider, (_, next) {
      if (next != null) _consumeNavRequest();
    });
    final permissionAsync = ref.watch(locationPermissionProvider);

    return permissionAsync.when(
      skipLoadingOnReload: true,
      data: (access) => switch (access) {
        LocationAccess.granted => _buildLocationView(context),
        _ => _LocationDeniedView(access: access),
      },
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
      skipLoadingOnReload: true,
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
    _deviceLat = deviceLat;
    _deviceLng = deviceLng;
    final destPoint = activeTrip?.destinationPoint;
    _navDestination = destPoint == null
        ? null
        : NearbyPlace(
            name: activeTrip!.destinationName ?? 'Destination',
            placeId: 'trip:${activeTrip.id}',
            category: 'Trip destination',
            location: Geo.pos(destPoint.lat, destPoint.lng),
          );
    // Several trips can be live at once; the map follows one and this lets the
    // user switch.
    final activeTrips =
        ref.watch(activeTripsProvider).valueOrNull ?? const <Trip>[];
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
        vehicleType: vehicleType,
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

    _latestTeammates = teammates;
    _scheduleNavUpdate(
      deviceLat,
      deviceLng,
      deviceSpeedMps > 1.0 && deviceHeadingDegrees >= 0
          ? deviceHeadingDegrees
          : (_compass ?? _lastCourse),
    );
    _watchForDrive(
      deviceSpeedMps,
      eligible: activeTrip == null && convoyGroupId == null,
    );
    _trackFollowedTeammate(teammates);
    _refreshMemberRoute(teammates);

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
    final minimal = ref.watch(appSettingsProvider.select((s) => s.mapMinimal));

    // Live speed for the badge comes from [liveSpeedMpsProvider], which decays
    // to zero when the distance-filtered GPS stream goes quiet — so it drops
    // when the traveller stops instead of freezing at the last moving value.
    // Null before the first fix hides the badge.
    final liveSpeedMps = ref.watch(liveSpeedMpsProvider).valueOrNull;

    final mapPostsAsync = activeTrip == null
        ? null
        : ref.watch(tripMapPostsProvider(activeTrip.id));
    // The trip pins (everyone) plus all of the user own, so personal pins show
    // whether or not a trip is running.
    final myPosts =
        ref.watch(myMapPostsProvider).valueOrNull ?? const <MapPost>[];
    final mapPosts = <MapPost>[
      ...(mapPostsAsync?.valueOrNull ?? const <MapPost>[]),
      ...myPosts,
    ];
    final seenPostIds = <String>{};
    mapPosts.retainWhere((p) => seenPostIds.add(p.id));

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
      final movingHeading = deviceSpeedMps > 1.0 && deviceHeadingDegrees >= 0
          ? deviceHeadingDegrees
          : null;
      // Remember the last real course so the beam holds its direction when the
      // vehicle stops, instead of snapping back to north.
      if (movingHeading != null) _lastCourse = movingHeading;
      unawaited(
        _beam.sync(
          map,
          lat: deviceLat,
          lng: deviceLng,
          headingDegrees:
              _compass ??
              movingHeading ??
              _lastCourse ??
              (_alwaysShowBeam ? 0 : null),
          colorArgb: BrandColors.primary.toARGB32(),
          // Standard/Satellite draw custom layers under the basemap unless slotted.
          slot: _style.isStandard ? 'top' : null,
        ),
      );
      unawaited(_syncTeammatePins(teammates, devicePixelRatio));
      unawaited(_syncPhotoPins(mapPosts, devicePixelRatio));
      unawaited(_syncSavedPlacePins(savedPlaces, devicePixelRatio));
      unawaited(_syncRoute(routePolyline));
      unawaited(_syncSelectedPlace(devicePixelRatio));
    }

    // The map is full-bleed (under the status bar), but its floating overlays
    // must clear a notch/status bar — FScaffold has no header here to inset them.
    // MediaQuery's top padding can be zeroed by an ancestor scaffold (which is
    // what put the pills under the Android status bar), so also read the real
    // system inset from the view — Android draws edge-to-edge under its bar.
    final view = View.of(context);
    final topInset = math.max(
      MediaQuery.paddingOf(context).top,
      view.padding.top / view.devicePixelRatio,
    );

    return FScaffold(
      childPad: false,
      child: // The map's overlays (IconButton, InkWell, FilledButton…) are Material
          // widgets, but FScaffold provides no Material ancestor — without this they
          // throw "No Material widget found" and render as a red error box.
          Material(
            type: MaterialType.transparency,
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
                  onStyleReloading: () =>
                      unawaited(_disposeAnnotationManagers()),
                  onUserPan: () {
                    _stopFollowing();
                    if (_navEngine != null && _navFollow) {
                      setState(() => _navFollow = false);
                    }
                  },
                  onCameraChanged: (data) {
                    final map = _mapKey.currentState?.map;
                    if (map != null) {
                      unawaited(
                        _beam.onCameraChanged(map, data.cameraState.zoom),
                      );
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
                if (_followingUserId != null)
                  Positioned(
                    top: 56 + topInset,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _stopFollowing,
                        child: BrandPill(
                          label:
                              'Following @${teammates.where((t) => t.userId == _followingUserId).firstOrNull?.username ?? 'teammate'} · tap to stop',
                          icon: Icons.my_location_rounded,
                          background: BrandColors.primary,
                          foreground: BrandColors.onPrimary,
                          iconColor: BrandColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                // Minimal map: just two small buttons — bring the UI back, or
                // recenter. Everything else is out of the way.
                if (minimal)
                  Positioned(
                    top: 16 + topInset + (_nav != null ? 140 : 0),
                    right: 16,
                    child: FloatingPanel(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MapControl(
                            icon: Icons.visibility_rounded,
                            tooltip: 'Show controls',
                            onTap: () {
                              AppFeedback.selection();
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setMapMinimal(false);
                            },
                          ),
                          _MapControl(
                            icon: Icons.my_location_rounded,
                            tooltip: 'Recenter on me',
                            onTap: () {
                              _stopFollowing();
                              _mapKey.currentState?.flyTo(
                                here,
                                zoom: kFollowZoom,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!minimal)
                  Positioned(
                    top: 16 + topInset + (_nav != null ? 140 : 0),
                    right: 16,
                    child: FloatingPanel(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MapControl(
                            icon: Icons.visibility_off_rounded,
                            tooltip: 'Hide controls',
                            onTap: () {
                              AppFeedback.selection();
                              ref
                                  .read(appSettingsProvider.notifier)
                                  .setMapMinimal(true);
                            },
                          ),
                          _MapControl(
                            icon: Icons.notifications_none_rounded,
                            tooltip: 'Notifications',
                            badgeCount:
                                ref
                                    .watch(unreadNotificationsProvider)
                                    .valueOrNull ??
                                0,
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
                            onTap: () {
                              _stopFollowing();
                              _mapKey.currentState?.flyTo(
                                here,
                                zoom: kFollowZoom,
                              );
                            },
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
                          _MapControl(
                            icon: Icons.add_a_photo_outlined,
                            tooltip: 'Pin a photo to the map',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AddMapPostScreen(
                                  tripId: activeTrip?.id,
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
                // Turn-by-turn instruction banner.
                if (_nav != null)
                  Positioned(
                    top: 8 + topInset,
                    left: 12,
                    right: 12,
                    child: NavBanner(
                      progress: _nav!,
                      unit: unit,
                      rerouting: _rerouting,
                    ),
                  ),
                // Live-convoy status pill, centred just below the status bar.
                if (_nav == null && !minimal)
                  Positioned(
                    top: 8 + topInset,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasLiveScope)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: BrandColors.surface.withValues(
                                  alpha: 0.92,
                                ),
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
                                        ? ''
                                        : !shareLocation
                                        ? 'Location sharing paused'
                                        : memberLocations.isEmpty
                                        ? 'Trip live'
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
                            if (hasLiveScope)
                              const SizedBox(width: BrandSpace.sm),
                            BrandPill(
                              label: formatSpeed(liveSpeedMps * 3.6, unit),
                              icon: Icons.speed_rounded,
                              background: BrandColors.surface.withValues(
                                alpha: 0.92,
                              ),
                              foreground: BrandColors.textHeadline,
                              iconColor: BrandColors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                // Minimal map keeps only what the user started: a selected place
                // or an active route.
                if (!minimal || _selectedPlace != null || _nav != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    // With the tab bar hidden the card must clear the gesture bar.
                    bottom:
                        16 +
                        (minimal
                            ? MediaQuery.viewPaddingOf(context).bottom
                            : 0),
                    child: BrandCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The selected place (nearby result, tapped POI, or dropped
                          // pin) with a Directions action and route summary.
                          if (_nav != null)
                            NavBottomBar(
                              progress: _nav!,
                              unit: unit,
                              following: _navFollow,
                              onRecenter: () {
                                setState(() => _navFollow = true);
                                _followNavCamera(
                                  deviceLat,
                                  deviceLng,
                                  _compass ?? _lastCourse,
                                );
                              },
                              onEnd: _endNavigation,
                            ),
                          if (_nav == null && _selectedPlace != null) ...[
                            if (_isNavTarget(_selectedPlace!)) ...[
                              _buildNavTargets(),
                              const SizedBox(height: BrandSpace.sm),
                            ],
                            _buildPlaceCard(deviceLat, deviceLng),
                            const SizedBox(height: BrandSpace.sm),
                          ],
                          // Live roster: each teammate's avatar + how far away they are,
                          // tap to navigate to them.
                          if (_nav == null && teammates.isNotEmpty) ...[
                            // Sized by its content, not a fixed height: the chip
                            // is avatar + name + distance, so a fixed box
                            // overflowed as soon as the text scale grew.
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final (i, teammate)
                                      in teammates.indexed) ...[
                                    if (i > 0)
                                      const SizedBox(width: BrandSpace.md),
                                    _TeammateChip(
                                      teammate: teammate,
                                      meters: haversineMeters(
                                        deviceLat,
                                        deviceLng,
                                        teammate.lat,
                                        teammate.lng,
                                      ),
                                      // Real initial bearing so the arrow points
                                      // at them.
                                      bearing: _initialBearingRadians(
                                        deviceLat,
                                        deviceLng,
                                        teammate.lat,
                                        teammate.lng,
                                      ),
                                      unit: unit,
                                      onTap: () => _openTeammate(teammate),
                                    ),
                                  ],
                                ],
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
                          // The "no convoy" prompt would only crowd a selected place
                          // or active navigation.
                          if (_nav != null || _selectedPlace != null)
                            const SizedBox.shrink()
                          else if (!hasLiveScope)
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
                                      color: BrandColors.secondaryFixed
                                          .withValues(alpha: 0.5),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          activeTrip?.title ??
                                              convoyGroupName ??
                                              'Your crew',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              BrandText.weight(
                                                BrandText.titleSm,
                                                700,
                                              ).copyWith(
                                                color: BrandColors.textHeadline,
                                              ),
                                        ),
                                        Text(
                                          memberLocations.isEmpty
                                              ? (activeTrip != null
                                                    ? 'Riding solo'
                                                    : 'Waiting for your crew')
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
                                  if (activeTrip != null &&
                                      activeTrip.createdBy ==
                                          SupabaseService.currentUser?.id &&
                                      memberLocations.isEmpty)
                                    IconButton(
                                      tooltip: 'End ride',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.stop_circle_rounded,
                                        color: BrandColors.error,
                                      ),
                                      onPressed: () => _endRide(activeTrip),
                                    ),
                                  if (_navDestination != null)
                                    IconButton(
                                      tooltip: 'Navigate to destination',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.flag_rounded,
                                        color: BrandColors.primary,
                                      ),
                                      onPressed: () =>
                                          _navigateTo(_navDestination!),
                                    ),
                                  if (activeTrips.length > 1)
                                    IconButton(
                                      tooltip: 'Switch trip',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.swap_horiz_rounded,
                                        color: BrandColors.primary,
                                      ),
                                      onPressed: () => _pickActiveTrip(
                                        activeTrips,
                                        activeTrip,
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
          ),
    );
  }

  /// One selectable route in the card: time, distance, and how it compares to
  /// the fastest.
  Widget _routeOption(int i, RouteOption route, {required int fastestSeconds}) {
    final selected = i == _previewIndex;
    final extraMinutes = ((route.durationSeconds - fastestSeconds) / 60)
        .round();
    return InkWell(
      borderRadius: BrandRadii.cardRadius,
      onTap: () {
        setState(() => _previewIndex = i);
        unawaited(_fitRoute(route.points));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? BrandColors.secondaryFixed.withValues(alpha: 0.45)
              : Colors.transparent,
          borderRadius: BrandRadii.cardRadius,
          border: Border.all(
            color: selected ? BrandColors.primary : BrandColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? BrandColors.primary : BrandColors.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              route.durationLabel,
              style: BrandText.weight(
                BrandText.titleSm,
                700,
              ).copyWith(color: BrandColors.textHeadline),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${route.distanceLabel} · via ${route.summary}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ),
            if (i == 0)
              BrandPill(label: 'Fastest')
            else if (extraMinutes > 0)
              Text(
                '+$extraMinutes min',
                style: BrandText.labelMd.copyWith(color: BrandColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  /// Pins a photo at the selected place (a dropped pin or tapped POI). It joins
  /// the running trip when there is one; otherwise it is a personal pin.
  Future<void> _pinPhotoAt(NearbyPlace place) async {
    // Await the provider so a still-loading trip is not misread as none.
    Trip? trip;
    try {
      trip = await ref.read(activeTripProvider.future);
    } catch (_) {
      trip = null;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddMapPostScreen(
          tripId: trip?.id,
          lat: place.location.lat.toDouble(),
          lng: place.location.lng.toDouble(),
        ),
      ),
    );
  }

  /// The card for [_selectedPlace]: name, a Directions button, and — once
  /// routes are loaded — the ETA, alternatives, and a hand-off to Maps.
  Widget _buildPlaceCard(double lat, double lng) {
    final place = _selectedPlace!;
    final routes = _previewRoutes;
    final chosen = routes.isEmpty ? null : routes[_previewIndex];
    final subtitle = chosen != null
        ? '${chosen.durationLabel} · ${chosen.distanceLabel}'
        : (place.category?.replaceAll('_', ' ') ??
              (place.placeId.startsWith('pin:')
                  ? '${place.location.lat.toStringAsFixed(4)}, ${place.location.lng.toStringAsFixed(4)}'
                  : 'Place'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Tapping the name opens the same rich details sheet the nearby
            // search shows, so a tapped POI can surface photos/contact info —
            // only when there's a real name for Google to resolve.
            Expanded(
              child: InkWell(
                borderRadius: BrandRadii.cardRadius,
                onTap: _canShowDetails(place)
                    ? () => _openPlaceDetails(place, lat, lng)
                    : null,
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
                        Icons.place_rounded,
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
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrandText.weight(
                              BrandText.titleSm,
                              700,
                            ).copyWith(color: BrandColors.textHeadline),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrandText.bodySm.copyWith(
                              color: BrandColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Send in chat',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.send_rounded, color: BrandColors.textMuted),
              onPressed: () => showShareToSheet(
                context,
                ref,
                title: 'Share place',
                share: ChatShare.location(
                  lat: place.location.lat.toDouble(),
                  lng: place.location.lng.toDouble(),
                  name: place.name,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, color: BrandColors.textMuted),
              onPressed: _clearSelectedPlace,
            ),
          ],
        ),
        if (_previewError != null) ...[
          const SizedBox(height: BrandSpace.xs),
          Text(
            _previewError!,
            style: BrandText.bodySm.copyWith(color: BrandColors.error),
          ),
        ],
        if (routes.length > 1) ...[
          const SizedBox(height: BrandSpace.sm),
          for (final (i, route) in routes.indexed)
            _routeOption(
              i,
              route,
              fastestSeconds: routes.first.durationSeconds,
            ),
        ],
        const SizedBox(height: BrandSpace.sm),
        if (chosen == null)
          Row(
            children: [
              Expanded(
                child: BrandPrimaryButton(
                  label: _previewLoading
                      ? 'Finding route…'
                      : (_previewError != null ? 'Try again' : 'Directions'),
                  leadingIcon: Icons.directions_rounded,
                  loading: _previewLoading,
                  // Tapping again while loading would double-fire; cancelling
                  // is the close button (or the route-cancel row below).
                  onPressed: _previewLoading
                      ? null
                      : () => _previewDirections(lat, lng),
                ),
              ),
              if (!_isNavTarget(place)) ...[
                const SizedBox(width: BrandSpace.sm),
                BrandSecondaryButton(
                  label: 'Photo',
                  expand: false,
                  leading: Icon(
                    Icons.add_a_photo_outlined,
                    size: 18,
                    color: BrandColors.textHeadlineAlt,
                  ),
                  onPressed: () => _pinPhotoAt(place),
                ),
              ],
            ],
          )
        else ...[
          BrandPrimaryButton(
            label: 'Start',
            leadingIcon: Icons.navigation_rounded,
            trailingIcon: null,
            onPressed: _startNavigation,
          ),
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              if (!_isNavTarget(place)) ...[
                Expanded(
                  child: BrandSecondaryButton(
                    label: 'Use for trip',
                    leading: Icon(
                      Icons.route_rounded,
                      size: 18,
                      color: BrandColors.textHeadlineAlt,
                    ),
                    onPressed: () => _useRouteForTrip(lat, lng),
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
              ],
              Expanded(
                child: BrandSecondaryButton(
                  label: _isNavTarget(place) ? 'Stop' : 'Cancel',
                  leading: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: BrandColors.textHeadlineAlt,
                  ),
                  onPressed: _cancelRoutePreview,
                ),
              ),
            ],
          ),
        ],
        if (_previewLoading) ...[
          const SizedBox(height: BrandSpace.xs),
          Center(
            child: TextButton(
              onPressed: _cancelRoutePreview,
              child: const Text('Cancel'),
            ),
          ),
        ],
      ],
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
    final here = Geo.pos(deviceLat, deviceLng);

    Widget chip(
      IconData icon,
      String label,
      VoidCallback onTap, {
      VoidCallback? onLongPress,
    }) => InkWell(
      borderRadius: BrandRadii.pill,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: BrandColors.surfaceContainerLow,
          borderRadius: BrandRadii.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: BrandColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: BrandText.labelMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The map's front door: where to? Works for any trip, with or without a
        // crew.
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _searchNearby(here),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: BrandColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: BrandColors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Where to?',
                    style: BrandText.bodyMd.copyWith(
                      color: BrandColors.textMuted,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BrandSpace.sm),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final label in const ['Home', 'Work']) ...[
                chip(
                  label == 'Home' ? Icons.home_rounded : Icons.work_rounded,
                  _shortcut(savedPlaces, label) == null ? 'Add $label' : label,
                  () => _onShortcutTap(label, savedPlaces, here),
                  onLongPress: _shortcut(savedPlaces, label) == null
                      ? null
                      : () => _shortcutMenu(label, savedPlaces, here),
                ),
                const SizedBox(width: BrandSpace.sm),
              ],
              chip(
                Icons.local_gas_station_rounded,
                'Fuel',
                () => _searchNearby(here, type: 'gas_station'),
              ),
              const SizedBox(width: BrandSpace.sm),
              chip(
                Icons.restaurant_rounded,
                'Food',
                () => _searchNearby(here, type: 'restaurant'),
              ),
              const SizedBox(width: BrandSpace.sm),
              chip(
                Icons.landscape_rounded,
                'Sights',
                () => _searchNearby(here, type: 'tourist_attraction'),
              ),
              const SizedBox(width: BrandSpace.sm),
              chip(
                Icons.bookmark_rounded,
                'Saved',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SavedPlacesScreen()),
                ),
              ),
            ],
          ),
        ),
        // Places the user (or the AI copilot) saved, when there are any.
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
        // The app is about riding together: planning a trip with a crew is the
        // main action. Recording a solo ride stays one tap away, but quieter.
        BrandPrimaryButton(
          label: 'Plan a trip with your crew',
          leadingIcon: Icons.groups_rounded,
          trailingIcon: null,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const NewTripScreen())),
        ),
        const SizedBox(height: BrandSpace.sm),
        BrandSecondaryButton(
          label: _startingRide ? 'Starting…' : 'Just ride solo',
          leading: Icon(
            Icons.play_arrow_rounded,
            size: 18,
            color: BrandColors.textHeadlineAlt,
          ),
          onPressed: _startingRide
              ? null
              : () => _startQuickRide(deviceLat, deviceLng),
        ),
      ],
    );
  }

  /// The saved place named [name] (Home / Work), if the user has set one.
  SavedPlace? _shortcut(List<SavedPlace> places, String name) {
    for (final p in places) {
      if (p.hasLocation && p.name.trim().toLowerCase() == name.toLowerCase()) {
        return p;
      }
    }
    return null;
  }

  void _onShortcutTap(String name, List<SavedPlace> places, Position here) {
    final place = _shortcut(places, name);
    if (place == null) {
      unawaited(_setShortcut(name, places, here));
      return;
    }
    final point = place.point!;
    unawaited(
      _navigateTo(
        NearbyPlace(
          name: name,
          placeId: 'pin:${name.toLowerCase()}',
          category: name,
          location: Geo.pos(point.lat, point.lng),
        ),
      ),
    );
  }

  void _shortcutMenu(String name, List<SavedPlace> places, Position here) {
    showAppActionSheet(
      context,
      title: name,
      actions: [
        AppSheetAction(
          label: 'Change $name',
          icon: Icons.edit_location_alt_rounded,
          onSelected: () => _setShortcut(name, places, here),
        ),
        AppSheetAction(
          label: 'Remove $name',
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () async {
            final existing = _shortcut(places, name);
            if (existing == null) return;
            try {
              await ref
                  .read(savedPlaceRepositoryProvider)
                  .deletePlace(existing.id);
              ref.invalidate(savedPlacesProvider);
            } catch (e) {
              if (mounted) showAppToast(context, friendlyError(e), error: true);
            }
          },
        ),
      ],
    );
  }

  /// Lets the user pick where Home / Work is, replacing any previous one.
  Future<void> _setShortcut(
    String name,
    List<SavedPlace> places,
    Position here,
  ) async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) =>
            PickLocationScreen(initialCenter: here, title: 'Set $name'),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final repo = ref.read(savedPlaceRepositoryProvider);
      final old = _shortcut(places, name);
      await repo.createPlace(
        name: name,
        lat: picked.position.lat.toDouble(),
        lng: picked.position.lng.toDouble(),
      );
      if (old != null) await repo.deletePlace(old.id);
      ref.invalidate(savedPlacesProvider);
      if (mounted) showAppToast(context, '$name saved.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  // --- drive detection -------------------------------------------------------

  DateTime? _fastSince;
  DateTime? _suggestCooldownUntil;

  /// Offers to record a ride once the device has moved at driving speed for a
  /// while with no trip running. Sustained speed (not one noisy fix) triggers
  /// it, and a dismissal is respected for 45 minutes.
  void _watchForDrive(double speedMps, {required bool eligible}) {
    if (!eligible || !ref.read(appSettingsProvider).suggestRides) {
      _fastSince = null;
      return;
    }
    if (speedMps < 4) {
      _fastSince = null;
      return;
    }
    if (speedMps < 7) return; // walking-to-driving grey zone: keep the clock
    final now = DateTime.now();
    _fastSince ??= now;
    if (now.difference(_fastSince!) < const Duration(seconds: 20)) return;
    final until = _suggestCooldownUntil;
    if (until != null && now.isBefore(until)) return;
    _suggestCooldownUntil = now.add(const Duration(minutes: 45));
    _fastSince = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showFToast(
        context: context,
        title: const Text('Looks like you are on the move'),
        description: const Text('Record this ride?'),
        icon: const Icon(Icons.speed_rounded),
        alignment: FToastAlignment.bottomCenter,
        duration: const Duration(seconds: 10),
        suffixBuilder: (context, entry) => FButton(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          onPress: () {
            entry.dismiss();
            final lat = _deviceLat;
            final lng = _deviceLng;
            if (lat != null && lng != null) {
              unawaited(_startQuickRide(lat, lng));
            }
          },
          child: const Text('Record'),
        ),
      );
    });
  }

  bool _startingRide = false;

  /// Starts a solo ride in one tap: creates a trip with just the user in it and
  /// activates it, so stats, history, odometer and photo pins all work with no
  /// planning and no crew. Others can still be invited to it later.
  Future<void> _startQuickRide(double lat, double lng) async {
    if (_startingRide) return;
    setState(() => _startingRide = true);
    try {
      final repo = ref.read(tripRepositoryProvider);
      final stamp = DateFormat.MMMd().add_jm().format(DateTime.now());
      final trip = await repo.createTrip(
        Trip.draft(
          createdBy: SupabaseService.currentUserId,
          title: 'Ride · $stamp',
          originName: 'Current location',
          originPoint: LatLngPoint(lat, lng),
        ),
      );
      await repo.startTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _startingRide = false);
    }
  }

  /// Ends a solo ride and shows its recap.
  Future<void> _endRide(Trip trip) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'End ride?',
      message: 'This finishes the ride and saves your stats.',
      confirmLabel: 'End ride',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(tripRepositoryProvider).completeTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
      ref.invalidate(tripStatsProvider(trip.id));
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => TripRecapScreen(trip: trip)));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
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

      if (!_live(manager)) return;
      await manager.deleteAll();
      if (!_live(manager)) return;
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

  /// Keeps one avatar pin above each live teammate's vehicle. Positions arrive
  /// about once a second, so existing pins are moved in place; the pins are only
  /// rebuilt when the set of teammates (or an avatar) changes. Overlapping calls
  /// collapse to "run once more with the latest data".
  Future<void> _syncTeammatePins(
    List<_Teammate> teammates,
    double devicePixelRatio,
  ) async {
    _latestTeammates = teammates;
    final manager = _teammatePoints;
    if (manager == null) return;
    if (_teammateSyncBusy) {
      _teammateSyncQueued = true;
      return;
    }
    _teammateSyncBusy = true;
    // Read theme colours before any await.
    final color = NavColors.of(context).activeRoute;
    try {
      do {
        _teammateSyncQueued = false;
        await _applyTeammatePins(
          manager,
          _latestTeammates,
          color,
          devicePixelRatio,
        );
      } while (_teammateSyncQueued &&
          mounted &&
          identical(manager, _teammatePoints));
    } catch (error) {
      _reportOverlaySyncFailure('teammate pins', error);
    } finally {
      _teammateSyncBusy = false;
    }
  }

  Future<void> _applyTeammatePins(
    PointAnnotationManager manager,
    List<_Teammate> teammates,
    Color color,
    double devicePixelRatio,
  ) async {
    final key = [for (final t in teammates) '${t.userId}:${t.avatarId}']
        .join('|');

    if (key != _renderedTeammateKey) {
      final images = <String, Uint8List>{};
      for (final t in teammates) {
        images[t.avatarId] ??= await MapMarkers.avatarPin(
          t.avatarId,
          color,
          devicePixelRatio: devicePixelRatio,
        );
      }
      if (!_live(manager) || !identical(manager, _teammatePoints)) return;
      await manager.deleteAll();
      _teammateAnnotations.clear();
      _userByAnnotationId.clear();
      _teammateLast.clear();
      if (teammates.isNotEmpty && _live(manager)) {
        final created = await manager.createMulti([
          for (final t in teammates)
            PointAnnotationOptions(
              geometry: Geo.point(t.lat, t.lng),
              image: images[t.avatarId],
              iconAnchor: IconAnchor.BOTTOM,
              // Lift the pin's tip clear of the vehicle so it floats over it.
              iconOffset: [0, -8],
            ),
        ]);
        for (var i = 0; i < created.length && i < teammates.length; i++) {
          final annotation = created[i];
          if (annotation == null) continue;
          final t = teammates[i];
          _teammateAnnotations[t.userId] = annotation;
          _userByAnnotationId[annotation.id] = t.userId;
          _teammateLast[t.userId] = (t.lat, t.lng);
        }
      }
      _renderedTeammateKey = key;
      return;
    }

    for (final t in teammates) {
      final annotation = _teammateAnnotations[t.userId];
      final last = _teammateLast[t.userId];
      if (annotation == null) continue;
      if (!_live(manager)) return;
      if (last != null && last.$1 == t.lat && last.$2 == t.lng) continue;
      annotation.geometry = Geo.point(t.lat, t.lng);
      await manager.update(annotation);
      _teammateLast[t.userId] = (t.lat, t.lng);
    }
  }

  /// Tapping a teammate's avatar pin opens their details (and directions).
  void _onTeammateTap(PointAnnotation annotation) {
    final userId = _userByAnnotationId[annotation.id];
    if (userId == null) return;
    final teammate = _latestTeammates
        .where((t) => t.userId == userId)
        .firstOrNull;
    if (teammate != null) unawaited(_openTeammate(teammate));
  }

  Future<void> _openTeammate(_Teammate teammate) async {
    if (!mounted) return;
    final following = _followingUserId == teammate.userId;
    await showNavigateToMemberSheet(
      context,
      destination: Geo.pos(teammate.lat, teammate.lng),
      username: teammate.username,
      userId: teammate.userId,
      vehicleType: ref.read(myProfileProvider).valueOrNull?.vehicleType,
      following: following,
      onNavigate: () => _navigateToMember(teammate),
      onShow: () {
        _stopFollowing();
        unawaited(
          _mapKey.currentState?.flyTo(
            Geo.pos(teammate.lat, teammate.lng),
            zoom: kFollowZoom,
          ),
        );
      },
      onToggleFollow: () {
        if (following) {
          _stopFollowing();
          return;
        }
        setState(() {
          _followingUserId = teammate.userId;
          _followLast = (teammate.lat, teammate.lng);
        });
        unawaited(
          _mapKey.currentState?.flyTo(
            Geo.pos(teammate.lat, teammate.lng),
            zoom: kFollowZoom,
          ),
        );
      },
    );
  }

  void _stopFollowing() {
    if (_followingUserId == null) return;
    setState(() {
      _followingUserId = null;
      _followLast = null;
    });
  }

  /// Keeps the camera on the locked teammate as their live position updates.
  /// Called from build, so state changes are deferred a frame.
  void _trackFollowedTeammate(List<_Teammate> teammates) {
    final id = _followingUserId;
    if (id == null) return;
    final target = teammates.where((t) => t.userId == id).firstOrNull;
    if (target == null) {
      // They stopped sharing or aged out: nothing left to follow.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _followingUserId != id) return;
        _stopFollowing();
        showAppToast(context, 'Lost their live location — stopped following.');
      });
      return;
    }
    final at = (target.lat, target.lng);
    if (_followLast == at) return;
    _followLast = at;
    unawaited(_mapKey.currentState?.easeTo(Geo.pos(at.$1, at.$2)));
  }

  // ---------------------------------------------------------------------------
  // Turn-by-turn navigation
  // ---------------------------------------------------------------------------

  /// Begins guidance along the route currently previewed.
  void _startNavigation() {
    final lat = _deviceLat;
    final lng = _deviceLng;
    if (_previewRoutes.isEmpty || lat == null || lng == null) return;
    final route = _previewRoutes[_previewIndex];
    final engine = NavEngine(route);
    AppFeedback.medium();
    AppFeedback.play(Sfx.navStart);
    setState(() {
      // Only the chosen road stays on the map while driving.
      _previewRoutes = [route];
      _previewIndex = 0;
      _navEngine = engine;
      _nav = engine.update(lat, lng);
      _navFollow = true;
      _offRouteFixes = 0;
      _announcedStep = null;
      _closeStep = null;
      _navLastFix = (lat, lng);
    });
    _followNavCamera(lat, lng, _compass ?? _lastCourse);
  }

  void _followNavCamera(double lat, double lng, double? heading) {
    unawaited(
      _mapKey.currentState?.followCamera(
        Geo.pos(lat, lng),
        bearing: heading,
        zoom: 17,
        pitch: 55,
      ),
    );
  }

  /// Ends guidance. [arrived] celebrates; otherwise it's a plain cancel.
  void _endNavigation({bool arrived = false}) {
    if (_navEngine == null) return;
    final lat = _deviceLat;
    final lng = _deviceLng;
    setState(() {
      _navEngine = null;
      _nav = null;
      _rerouting = false;
      _navLastFix = null;
    });
    if (arrived) {
      AppFeedback.success();
      AppFeedback.play(Sfx.arrive);
      showAppToast(context, "You've arrived.");
    } else {
      AppFeedback.medium();
    }
    _clearSelectedPlace();
    if (lat != null && lng != null) {
      unawaited(
        _mapKey.currentState?.flyTo(
          Geo.pos(lat, lng),
          zoom: kFollowZoom,
          pitch: 45,
        ),
      );
    }
  }

  /// Called from build on every new fix; the real work happens after the frame
  /// so it can call setState.
  void _scheduleNavUpdate(double lat, double lng, double? heading) {
    if (_navEngine == null) return;
    if (_navLastFix == (lat, lng)) return;
    _navLastFix = (lat, lng);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _navEngine != null) _applyNavFix(lat, lng, heading);
    });
  }

  void _applyNavFix(double lat, double lng, double? heading) {
    final engine = _navEngine;
    if (engine == null) return;
    final progress = engine.update(lat, lng);
    setState(() => _nav = progress);

    if (progress.arrived) {
      _endNavigation(arrived: true);
      return;
    }
    if (_navFollow) _followNavCamera(lat, lng, heading);

    // Chime as a maneuver approaches: once at ~180 m, a tick again at ~40 m.
    final idx = progress.stepIndex;
    if (progress.step.type != 'arrive') {
      if (progress.metersToManeuver <= 180 && _announcedStep != idx) {
        _announcedStep = idx;
        AppFeedback.medium();
        AppFeedback.play(Sfx.turn);
      }
      if (progress.metersToManeuver <= 40 && _closeStep != idx) {
        _closeStep = idx;
        AppFeedback.heavy();
      }
    }

    // Off the route for several fixes in a row: fetch a new one.
    if (progress.offRouteMeters > NavEngine.offRouteThresholdMeters) {
      _offRouteFixes++;
      final last = _lastReroute;
      if (_offRouteFixes >= 3 &&
          !_rerouting &&
          (last == null ||
              DateTime.now().difference(last) > const Duration(seconds: 15))) {
        unawaited(_reroute(lat, lng));
      }
    } else {
      _offRouteFixes = 0;
    }
  }

  Future<void> _reroute(double lat, double lng) async {
    final place = _selectedPlace;
    if (place == null || _navEngine == null) return;
    _lastReroute = DateTime.now();
    setState(() => _rerouting = true);
    try {
      const modes = {'car', 'bike', 'scooter', 'suv', 'other'};
      final vehicle = ref.read(myProfileProvider).valueOrNull?.vehicleType;
      final routes = await GoogleMapsApiService.directions(
        origin: Geo.pos(lat, lng),
        destination: place.location,
        profile: modes.contains(vehicle) ? vehicle : null,
        withSteps: true,
      );
      if (!mounted || _navEngine == null) return;
      final engine = NavEngine(routes.first);
      AppFeedback.play(Sfx.reroute);
      setState(() {
        _previewRoutes = [routes.first];
        _previewIndex = 0;
        _navEngine = engine;
        _nav = engine.update(lat, lng);
        _announcedStep = null;
        _closeStep = null;
        _offRouteFixes = 0;
      });
    } catch (_) {
      // Keep guiding on the old route; try again after the cooldown.
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  /// Member and trip-destination targets are routed to, not browsed: no photo
  /// pinning, details sheet or "use for a trip".
  static bool _isNavTarget(NearbyPlace place) =>
      place.placeId.startsWith('member:') || place.placeId.startsWith('trip:');

  /// Draws an in-app route from the user's position to [place].
  Future<void> _navigateTo(NearbyPlace place) async {
    final lat = _deviceLat;
    final lng = _deviceLng;
    if (lat == null || lng == null) {
      showAppToast(context, 'Waiting for your location…');
      return;
    }
    _stopFollowing();
    _memberRouteAt = DateTime.now();
    await _selectPlace(place, fly: false);
    await _previewDirections(lat, lng);
  }

  Future<void> _navigateToMember(_Teammate t) => _navigateTo(
    NearbyPlace(
      name: t.username != null ? '@${t.username}' : 'Teammate',
      placeId: 'member:${t.userId}',
      category: 'Teammate',
      location: Geo.pos(t.lat, t.lng),
    ),
  );

  /// Handles a "navigate here" request raised elsewhere in the app (a location
  /// shared in chat, a saved place).
  void _consumeNavRequest() {
    final request = ref.read(mapNavRequestProvider);
    if (request == null || !mounted) return;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(mapNavRequestProvider.notifier).state = null;
      unawaited(
        _navigateTo(
          NearbyPlace(
            name: request.name,
            placeId: 'pin:shared',
            location: Geo.pos(request.lat, request.lng),
          ),
        ),
      );
    });
  }

  /// While navigating to a teammate, re-routes as they move (throttled: it
  /// costs a directions call) so the line follows them instead of going stale.
  void _refreshMemberRoute(List<_Teammate> teammates) {
    final place = _selectedPlace;
    if (place == null || !place.placeId.startsWith('member:')) return;
    if (_previewRoutes.isEmpty || _previewLoading) return;
    final id = place.placeId.substring('member:'.length);
    final t = teammates.where((t) => t.userId == id).firstOrNull;
    final lat = _deviceLat;
    final lng = _deviceLng;
    if (t == null || lat == null || lng == null) return;
    final moved = haversineMeters(
      place.location.lat.toDouble(),
      place.location.lng.toDouble(),
      t.lat,
      t.lng,
    );
    final last = _memberRouteAt;
    if (moved < 300 ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 30))) {
      return;
    }
    _memberRouteAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _selectedPlace?.placeId != place.placeId) return;
      setState(() {
        _selectedPlace = NearbyPlace(
          name: place.name,
          placeId: place.placeId,
          category: place.category,
          location: Geo.pos(t.lat, t.lng),
        );
      });
      await _previewDirections(lat, lng, fit: false);
    });
  }

  /// Switcher between navigation targets: the trip's destination and each
  /// live teammate. Shown while navigating to one of them.
  Widget _buildNavTargets() {
    final selectedId = _selectedPlace?.placeId;
    Widget chip(String label, IconData icon, String id, VoidCallback onTap) {
      final selected = selectedId == id;
      return InkWell(
        borderRadius: BrandRadii.pill,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? BrandColors.primary : Colors.transparent,
            borderRadius: BrandRadii.pill,
            border: Border.all(
              color: selected ? BrandColors.primary : BrandColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? BrandColors.onPrimary : BrandColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: BrandText.labelSm.copyWith(
                  color: selected
                      ? BrandColors.onPrimary
                      : BrandColors.textHeadline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final destination = _navDestination;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (destination != null) ...[
            chip(
              destination.name,
              Icons.flag_rounded,
              destination.placeId,
              () => _navigateTo(destination),
            ),
            const SizedBox(width: BrandSpace.sm),
          ],
          for (final t in _latestTeammates) ...[
            chip(
              t.username != null ? '@${t.username}' : 'Teammate',
              Icons.directions_car_filled_rounded,
              'member:${t.userId}',
              () => _navigateToMember(t),
            ),
            const SizedBox(width: BrandSpace.sm),
          ],
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
    // Skip only when the *same* manager already shows exactly these posts. A
    // replaced manager (style reload / map rebuild) must redraw even if the ids
    // are unchanged.
    if (identical(manager, _renderedPostManager) &&
        listEquals(ids, _renderedPostIds)) {
      return;
    }

    try {
      final color = NavColors.of(context).highway;

      // Photos pinned at nearly the same spot stack under one pin that carries a
      // count, instead of hiding behind each other.
      final stacks = stackPhotoPins(
        posts,
        radiusMeters: _photoStackRadiusMeters,
      );
      final images = <int, Uint8List>{};
      for (final stack in stacks) {
        images[stack.length] ??= await MapMarkers.pin(
          color,
          Icons.photo_camera_rounded,
          devicePixelRatio: devicePixelRatio,
          count: stack.length,
        );
      }

      if (!_live(manager)) return;
      await manager.deleteAll();
      _postByAnnotationId.clear();
      if (stacks.isNotEmpty && _live(manager)) {
        final created = await manager.createMulti([
          for (final stack in stacks)
            PointAnnotationOptions(
              geometry: Geo.point(stack.first.lat, stack.first.lng),
              image: images[stack.length],
              iconAnchor: IconAnchor.BOTTOM,
            ),
        ]);
        // `createMulti` preserves the input order, so the returned annotations
        // line up index-for-index with `stacks`.
        for (var i = 0; i < created.length && i < stacks.length; i++) {
          final annotation = created[i];
          if (annotation != null) {
            _postByAnnotationId[annotation.id] = stacks[i];
          }
        }
      }
      // Commit the guard only after the work succeeded, so a failure is retried
      // on the next rebuild instead of being permanently suppressed.
      _renderedPostIds = ids;
      _renderedPostManager = manager;
    } catch (error) {
      // A failed overlay sync must not take the map down — but don't hide it.
      _reportOverlaySyncFailure('photo pins', error);
    }
  }

  Future<void> _syncRoute(String? encodedPolyline) async {
    final map = _mapKey.currentState?.map;
    if (map == null) return;
    // Read theme colours before any await.
    final nav = NavColors.of(context);

    final List<Position> main;
    final List<List<Position>> alternatives;
    if (_previewRoutes.isNotEmpty) {
      // A directions preview takes over the line until it's dismissed.
      main = _previewRoutes[_previewIndex].points;
      alternatives = [
        for (final (i, r) in _previewRoutes.indexed)
          if (i != _previewIndex) r.points,
      ];
    } else {
      main = encodedPolyline == null ? const [] : _routePoints(encodedPolyline);
      alternatives = const [];
    }

    final previewing = _previewRoutes.isNotEmpty;
    await _routeRenderer.sync(
      map,
      main: main,
      alternatives: alternatives,
      // Time bubbles on each candidate route (only for a directions preview).
      mainLabel: previewing
          ? _previewRoutes[_previewIndex].durationLabel
          : null,
      altLabels: [
        for (final (i, r) in _previewRoutes.indexed)
          if (i != _previewIndex) r.durationLabel,
      ],
      mainColorArgb: nav.activeRoute.toARGB32(),
      casingColorArgb: 0xFFFFFFFF,
      altColorArgb: nav.altRoute.withValues(alpha: 0.75).toARGB32(),
      // Standard/Satellite hide slot-less layers under the basemap.
      slot: _style.isStandard ? 'top' : null,
    );
  }

  Future<void> _syncSelectedPlace(double devicePixelRatio) async {
    // A teammate is already on the map as a vehicle + avatar; no pin for them.
    final selected = _selectedPlace;
    final place = selected != null && selected.placeId.startsWith('member:')
        ? null
        : selected;
    if (_renderedPlaceId == place?.placeId) return;
    if (_mapKey.currentState?.map == null) return;
    final pinColor = NavColors.of(context).activeRoute;

    try {
      // The place pin lives on its own manager so it isn't wiped out every time
      // the photo set changes.
      final generation = _styleGeneration;
      if (_placePoints == null || !_live(_placePoints)) {
        final created = await _mapKey.currentState?.map?.annotations
            .createPointAnnotationManager();
        // A style reload during the await orphaned it; drop it.
        if (created == null || !mounted || generation != _styleGeneration) {
          return;
        }
        _placePoints = created;
        _liveManagers.add(created);
      }
      final placeManager = _placePoints;
      if (placeManager == null || !_live(placeManager)) return;

      _placePin ??= await MapMarkers.pin(
        pinColor,
        Icons.place_rounded,
        devicePixelRatio: devicePixelRatio,
      );
      final image = _placePin!;

      if (!_live(placeManager)) return;
      await placeManager.deleteAll();
      if (place != null && _live(placeManager)) {
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
    await _openTeammate(selected);
  }
}

/// Shows the Google Play prominent disclosure (once) and then raises the OS
/// location prompt. Kept apart from the provider so the prompt is only ever
/// triggered by an explicit user tap, never on first watch.
Future<void> _requestLocationPermission(
  BuildContext context,
  WidgetRef ref,
) async {
  final prefs = ref.read(appPrefsProvider);
  if (!prefs.locationDisclosureSeen) {
    final agreed = await showAppConfirmDialog(
      context,
      title: 'Share your location?',
      message:
          'Ranmap shares your live location with the members of your active '
          'trip or group so they can see you on the map and get safe-distance '
          'alerts. While a trip or convoy is active it keeps sharing in the '
          'background. Sharing stops when you leave, and you can pause it any '
          'time in Settings.',
      confirmLabel: 'Continue',
    );
    if (!agreed || !context.mounted) return;
    await prefs.markLocationDisclosureSeen();
  }
  await Geolocator.requestPermission();
  ref.invalidate(locationPermissionProvider);
}

class _LocationDeniedView extends ConsumerWidget {
  const _LocationDeniedView({required this.access});

  final LocationAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    // The three non-granted states need different fixes: the device's location
    // service (device settings), a permanent app block (app settings only), or
    // a plain denial (prompt again).
    final serviceOff = access == LocationAccess.serviceDisabled;
    final blocked = access == LocationAccess.deniedForever;
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
                switch (access) {
                  LocationAccess.serviceDisabled =>
                    'Location services are off. Turn them on so Ranmap can '
                        'show you on the map and keep your trip in sync with '
                        'your group.',
                  LocationAccess.deniedForever =>
                    'Location permission is blocked. Open Settings and allow '
                        'location so Ranmap can show you on the map and keep '
                        'your trip in sync with your group.',
                  _ =>
                    'Ranmap needs your location to show you on the map and keep '
                        'your trip in sync with your group.',
                },
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
                    } else if (blocked) {
                      // The OS won't prompt again, so Settings is the only way
                      // back; re-requesting here would silently no-op.
                      unawaited(Geolocator.openAppSettings());
                    } else {
                      // User-initiated: show the Play-required background-
                      // location disclosure, then raise the OS prompt.
                      unawaited(_requestLocationPermission(context, ref));
                    }
                  },
                  child: Text(switch (access) {
                    LocationAccess.serviceDisabled => 'Turn on location',
                    LocationAccess.deniedForever => 'Open settings',
                    _ => 'Allow location',
                  }),
                ),
              ),
              if (!serviceOff && !blocked) ...[
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
