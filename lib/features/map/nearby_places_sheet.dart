import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/units.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../data/models/route_option.dart';
import '../../data/services/google_maps_api_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'map_engine/map_engine.dart';
import 'place_details_sheet.dart';

const _kPlaceTypes = [
  ('restaurant', 'Food', Icons.restaurant_rounded),
  ('gas_station', 'Fuel', Icons.local_gas_station_rounded),
  ('lodging', 'Lodging', Icons.hotel_rounded),
  ('tourist_attraction', 'Sights', Icons.landscape_rounded),
];

/// The "how much a stop adds" line, e.g. `~12 min · 8.0 mi`, in the user's
/// distance unit.
String _detourLabel(PlaceDetour detour, DistanceUnit unit) {
  final minutes = (detour.durationSeconds / 60).round();
  return '~$minutes min · ${formatDistance(detour.distanceMeters / 1000, unit)}';
}

/// Search for nearby shops/POIs around [center]. When [routePolyline] is
/// supplied, the user can also search along that route. Tapping a result opens
/// its details, where it can be pinned on the map — returns the selected
/// [NearbyPlace], or null if dismissed without pinning.
Future<NearbyPlace?> showNearbyPlacesSheet(
  BuildContext context, {
  required Position center,
  String? routePolyline,
}) {
  return showFSheet<NearbyPlace>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    // The sheet already draws its own grab handle and manages its own layout
    // (a DraggableScrollableSheet), so the surface adds only the opaque
    // background, top rounding and bottom safe-area inset.
    builder: (_) => BrandSheetSurface(
      handle: false,
      padding: EdgeInsets.zero,
      child: _NearbyPlacesSheet(center: center, routePolyline: routePolyline),
    ),
  );
}

class _NearbyPlacesSheet extends ConsumerStatefulWidget {
  final Position center;
  final String? routePolyline;

  const _NearbyPlacesSheet({required this.center, this.routePolyline});

  @override
  ConsumerState<_NearbyPlacesSheet> createState() => _NearbyPlacesSheetState();
}

class _NearbyPlacesSheetState extends ConsumerState<_NearbyPlacesSheet> {
  String _type = _kPlaceTypes.first.$1;
  bool _alongRoute = false;
  List<NearbyPlace> _places = const [];
  bool _loading = true;
  String? _error;

  bool get _canSearchAlongRoute =>
      widget.routePolyline != null && widget.routePolyline!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final polyline = widget.routePolyline;
      final places = _alongRoute && polyline != null && polyline.isNotEmpty
          ? await GoogleMapsApiService.placesAlongRoute(
              routePolyline: polyline,
              // Anchor the detour figures: the server measures from here.
              origin: widget.center,
              category: _type,
            )
          : await GoogleMapsApiService.nearbyPlaces(
              center: widget.center,
              radiusMeters: 5000,
              category: _type,
            );
      if (!mounted) return;
      setState(() => _places = places);
    } catch (e) {
      if (!mounted) return;
      // An exhausted free search allowance is the one case where a paywall is
      // exactly right, rather than a raw error with no upgrade path.
      if (isPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.mapsSearch);
        return;
      }
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetails(NearbyPlace place) async {
    final pin = await showPlaceDetailsSheet(context, place);
    if (!mounted || pin != true) return;
    Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Grab handle.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kPlaceTypes.map((t) {
                  final (id, label, icon) = t;
                  final selected = _type == id;
                  return FButton(
                    variant: selected ? .primary : .outline,
                    size: .sm,
                    selected: selected,
                    onPress: () {
                      setState(() => _type = id);
                      _search();
                    },
                    prefix: Icon(icon),
                    child: Text(label),
                  );
                }).toList(),
              ),
            ),
            if (_canSearchAlongRoute)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: FSwitch(
                  label: const Text('Search along the route'),
                  value: _alongRoute,
                  onChange: (v) {
                    setState(() => _alongRoute = v);
                    _search();
                  },
                ),
              ),
            const FDivider(),
            Expanded(
              child: _loading
                  ? const Center(child: FCircularProgress())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(_error!, textAlign: TextAlign.center),
                            ),
                            const SizedBox(height: 14),
                            FButton(
                              onPress: _search,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _places.isEmpty
                  ? Center(
                      child: Text(
                        'No places found nearby.',
                        style: TextStyle(color: c.mutedForeground),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _places.length,
                      itemBuilder: (context, i) {
                        final place = _places[i];
                        final detour = place.detour;
                        return FTile(
                          prefix: Icon(
                            Icons.place_outlined,
                            color: c.activeRoute,
                          ),
                          title: Text(place.name),
                          // Only rendered when the server measured a detour;
                          // no placeholder when it didn't.
                          subtitle: detour == null
                              ? null
                              : Text(
                                  _detourLabel(detour, unit),
                                  style: BrandText.bodySm.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                          onPress: () => _openDetails(place),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
