import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/services/google_maps_api_service.dart';
import 'map_engine/map_engine.dart';

/// What [PickLocationScreen] returns: the picked point, plus the place's name
/// when it was chosen from a search result (and the map wasn't moved since).
class PickedLocation {
  const PickedLocation(this.position, {this.name});

  final Position position;
  final String? name;
}

/// Lets the user pick a point on the map — by searching for a place or address,
/// or by dragging the map under a fixed centre pin. Returns a [PickedLocation],
/// or null if cancelled.
class PickLocationScreen extends StatefulWidget {
  const PickLocationScreen({
    super.key,
    this.initialCenter,
    this.title = 'Pick a location',
  });

  /// Where to open the camera. Null falls back to a wide, pan-able world view
  /// (used when the user's location isn't known yet).
  final Position? initialCenter;
  final String title;

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  /// A search-result pick is only "the named place" while the pin is still on
  /// it; past this distance the user has moved on and the name is dropped.
  static const _nameKeepMeters = 75.0;

  final _mapKey = GlobalKey<RanmapMapViewState>();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<PlaceSuggestion> _suggestions = const [];
  GeocodeResult? _selected;
  bool _searching = false;
  String? _searchError;

  /// Discards results from a query the user has since edited.
  int _searchToken = 0;

  /// The Mapbox Search Box session, opened on the first keystroke of a burst and
  /// closed once a suggestion is resolved (see [retrieve]).
  String? _sessionToken;

  String _newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${math.Random().nextInt(1 << 32).toRadixString(16)}';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      _searchToken++;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    // Open the autocomplete session as soon as the user starts typing.
    _sessionToken ??= _newSessionToken();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final token = ++_searchToken;
    final session = _sessionToken ??= _newSessionToken();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final suggestions = await GoogleMapsApiService.suggest(
        query,
        sessionToken: session,
        near: widget.initialCenter,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = suggestions;
        _searchError = suggestions.isEmpty ? 'No matches for "$query".' : null;
      });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = const [];
        _searchError = friendlyError(e);
      });
    } finally {
      if (mounted && token == _searchToken) setState(() => _searching = false);
    }
  }

  /// Resolves a suggestion to coordinates (completing the session), then moves
  /// the pin there. A suggestion carries no geometry, so this needs the extra
  /// retrieve round-trip.
  Future<void> _choose(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    final token = ++_searchToken;
    final session = _sessionToken ??= _newSessionToken();
    setState(() {
      _searching = true;
      _searchError = null;
    });

    GeocodeResult? resolved;
    try {
      resolved = await GoogleMapsApiService.retrieve(
        suggestion.id,
        sessionToken: session,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = friendlyError(e);
        });
      }
      return;
    }
    if (!mounted || token != _searchToken) return;

    // The session ends once a suggestion is chosen.
    _sessionToken = null;

    if (resolved == null) {
      setState(() {
        _searching = false;
        _searchError = 'Could not load that place.';
      });
      return;
    }
    final place = resolved;
    setState(() {
      _selected = place;
      _suggestions = const [];
      _searching = false;
      _searchError = null;
      _searchCtrl.text = place.name;
    });
    unawaited(_mapKey.currentState?.flyTo(place.location, zoom: 15));
  }

  Future<void> _confirm() async {
    final map = _mapKey.currentState?.map;
    if (map == null) return;
    // The pin is fixed at the centre of the viewport, so the picked point is
    // simply wherever the camera is centered now.
    final camera = await map.getCameraState();
    if (!mounted) return;
    final center = camera.center.coordinates;
    final selected = _selected;
    final keepName =
        selected != null &&
        haversineMeters(
              selected.location.lat.toDouble(),
              selected.location.lng.toDouble(),
              center.lat.toDouble(),
              center.lng.toDouble(),
            ) <=
            _nameKeepMeters;
    Navigator.of(context)
        .pop(PickedLocation(center, name: keepName ? selected.label : null));
  }

  @override
  Widget build(BuildContext context) {
    final showPanel =
        _searching || _suggestions.isNotEmpty || _searchError != null;
    return BrandScaffold(
      header: BrandHeader(
        title: widget.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      // Full-bleed map: drop the shell's page margin so the camera fills the
      // viewport edge-to-edge.
      padding: EdgeInsets.zero,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RanmapMapView(
            key: _mapKey,
            center: widget.initialCenter,
            zoom: widget.initialCenter == null ? kFallbackMapZoom : 15,
            pitch: 0,
            showUserLocation: true,
          ),
          IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_pin,
                size: 48,
                color: BrandColors.primary,
              ),
            ),
          ),
          Positioned(
            left: BrandSpace.md,
            right: BrandSpace.md,
            top: BrandSpace.sm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandTextField(
                  controller: _searchCtrl,
                  hint: 'Search a place or address',
                  leadingIcon: Icons.search_rounded,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: (value) {
                    _debounce?.cancel();
                    if (value.trim().length >= 2) _search(value.trim());
                  },
                ),
                if (showPanel)
                  Padding(
                    padding: const EdgeInsets.only(top: BrandSpace.xs),
                    // ListTile needs a Material ancestor to paint its ink.
                    child: Material(
                      color: BrandColors.surface,
                      elevation: 3,
                      borderRadius: BrandRadii.cardRadius,
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(BrandSpace.md),
                                child: Center(
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : _searchError != null
                            ? Padding(
                                padding: const EdgeInsets.all(BrandSpace.md),
                                child: Text(
                                  _searchError!,
                                  style: BrandText.bodyMd.copyWith(
                                    color: BrandColors.textMuted,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _suggestions.length,
                                itemBuilder: (context, i) {
                                  final r = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      Icons.place_outlined,
                                      color: BrandColors.primary,
                                    ),
                                    title: Text(
                                      r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: r.address == null
                                        ? null
                                        : Text(
                                            r.address!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () => _choose(r),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: BrandSpace.lg,
            child: Center(
              child: BrandPrimaryButton(
                label: 'Use this spot',
                expand: false,
                trailingIcon: Icons.check_rounded,
                onPressed: _confirm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
