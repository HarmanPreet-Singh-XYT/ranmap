import 'dart:async';

import '../../core/widgets/haptic_switch.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/units.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_text_field.dart';
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

/// What the nearby sheet returns: the tapped [place], and whether the user
/// asked for directions to it (from the details sheet) rather than just pinning.
class NearbySelection {
  const NearbySelection(this.place, {this.startDirections = false});

  final NearbyPlace place;
  final bool startDirections;
}

/// The "how much a stop adds" line, e.g. `~12 min · 8.0 mi`, in the user's
/// distance unit.
String _detourLabel(PlaceDetour detour, DistanceUnit unit) {
  final minutes = (detour.durationSeconds / 60).round();
  return '~$minutes min · ${formatDistance(detour.distanceMeters / 1000, unit)}';
}

/// Search for nearby shops/POIs around [center] — by free-text query or a fixed
/// category chip. When [routePolyline] is supplied, the user can also search
/// along that route. Tapping a result opens its details, where it can be pinned
/// or routed to — returns the selection, or null if dismissed without choosing.
Future<NearbySelection?> showNearbyPlacesSheet(
  BuildContext context, {
  required Position center,
  String? routePolyline,
  String? initialType,
}) {
  return showFSheet<NearbySelection>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    // The sheet already draws its own grab handle and manages its own layout
    // (a DraggableScrollableSheet), so the surface adds only the opaque
    // background, top rounding and bottom safe-area inset.
    builder: (_) => BrandSheetSurface(
      handle: false,
      padding: EdgeInsets.zero,
      child: _NearbyPlacesSheet(
        center: center,
        routePolyline: routePolyline,
        initialType: initialType,
      ),
    ),
  );
}

class _NearbyPlacesSheet extends ConsumerStatefulWidget {
  final Position center;
  final String? routePolyline;
  final String? initialType;

  const _NearbyPlacesSheet({
    required this.center,
    this.routePolyline,
    this.initialType,
  });

  @override
  ConsumerState<_NearbyPlacesSheet> createState() => _NearbyPlacesSheetState();
}

class _NearbyPlacesSheetState extends ConsumerState<_NearbyPlacesSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _type = _kPlaceTypes.first.$1;
  bool _alongRoute = false;
  List<NearbyPlace> _places = const [];
  bool _loading = true;
  String? _error;

  /// Discards results from a query the user has since edited.
  int _searchToken = 0;

  bool get _isFreeText => _searchCtrl.text.trim().length >= 2;

  bool get _canSearchAlongRoute =>
      widget.routePolyline != null && widget.routePolyline!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final start = widget.initialType;
    if (start != null && _kPlaceTypes.any((t) => t.$1 == start)) _type = start;
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final wasFreeText = _isFreeText;
    if (value.trim().length < 2) {
      // Dropping back under the minimum returns to the category results — but
      // only when we were actually in free-text mode, so typing one character
      // from empty doesn't fire a needless category request.
      if (wasFreeText) {
        _search();
      } else {
        setState(() {});
      }
      return;
    }
    // Reflect the chip/free-text state immediately, then search once settled.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final polyline = widget.routePolyline;
      final places = query.length >= 2
          ? await GoogleMapsApiService.searchPlaces(query, near: widget.center)
          : _alongRoute && polyline != null && polyline.isNotEmpty
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
      if (!mounted || token != _searchToken) return;
      setState(() => _places = places);
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      // An exhausted free search allowance is the one case where a paywall is
      // exactly right, rather than a raw error with no upgrade path.
      if (isPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.mapsSearch);
        return;
      }
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && token == _searchToken) setState(() => _loading = false);
    }
  }

  void _selectCategory(String id) {
    // A pending free-text debounce must not fire after the chip tap and
    // double-fire a search.
    _debounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() => _type = id);
    _search();
  }

  void _clearQuery() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {});
    _search();
  }

  Future<void> _openDetails(NearbyPlace place) async {
    final action = await showPlaceDetailsSheet(context, place);
    if (!mounted || action == null) return;
    Navigator.of(context).pop(
      NearbySelection(
        place,
        startDirections: action == PlaceDetailsAction.directions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final freeText = _isFreeText;

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
              child: BrandTextField(
                controller: _searchCtrl,
                hint: 'Search for anything',
                leadingIcon: Icons.search_rounded,
                textInputAction: TextInputAction.search,
                trailing: _searchCtrl.text.isEmpty
                    ? null
                    : BrandFieldAction(
                        icon: Icons.close_rounded,
                        semanticLabel: 'Clear search',
                        onTap: _clearQuery,
                      ),
                onChanged: _onQueryChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  if (value.trim().length >= 2) _search();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kPlaceTypes.map((t) {
                  final (id, label, icon) = t;
                  final selected = !freeText && _type == id;
                  return FButton(
                    variant: selected ? .primary : .outline,
                    size: .sm,
                    selected: selected,
                    onPress: () => _selectCategory(id),
                    prefix: Icon(icon),
                    child: Text(label),
                  );
                }).toList(),
              ),
            ),
            // Along-route only makes sense for the category search; free-text
            // search is proximity-based.
            if (_canSearchAlongRoute && !freeText)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: HapticSwitch(
                  label: const Text('Search along the route'),
                  value: _alongRoute,
                  onChange: (v) {
                    setState(() => _alongRoute = v);
                    _search();
                  },
                ),
              ),
            const FDivider(),
            // A thin progress bar while refreshing, so an in-flight query
            // doesn't blank the results already on screen.
            if (_loading && _places.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading && _places.isEmpty
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
                        freeText
                            ? 'No places found for "${_searchCtrl.text.trim()}".'
                            : 'No places found nearby.',
                        style: TextStyle(color: c.mutedForeground),
                        textAlign: TextAlign.center,
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
