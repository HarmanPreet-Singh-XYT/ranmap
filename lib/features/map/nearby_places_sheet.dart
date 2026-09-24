import 'package:flutter/material.dart';

import '../../core/util/error_text.dart';
import '../../data/models/route_option.dart';
import '../../data/services/google_maps_api_service.dart';
import 'map_engine/map_engine.dart';
import 'place_details_sheet.dart';

const _kPlaceTypes = [
  ('restaurant', 'Food', Icons.restaurant_rounded),
  ('gas_station', 'Fuel', Icons.local_gas_station_rounded),
  ('lodging', 'Lodging', Icons.hotel_rounded),
  ('tourist_attraction', 'Sights', Icons.landscape_rounded),
];

/// Search for nearby shops/POIs around [center]. When [routePolyline] is
/// supplied, the user can also search along that route. Tapping a result opens
/// its details, where it can be pinned on the map — returns the selected
/// [NearbyPlace], or null if dismissed without pinning.
Future<NearbyPlace?> showNearbyPlacesSheet(
  BuildContext context, {
  required Position center,
  String? routePolyline,
}) {
  return showModalBottomSheet<NearbyPlace>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NearbyPlacesSheet(center: center, routePolyline: routePolyline),
  );
}

class _NearbyPlacesSheet extends StatefulWidget {
  final Position center;
  final String? routePolyline;

  const _NearbyPlacesSheet({required this.center, this.routePolyline});

  @override
  State<_NearbyPlacesSheet> createState() => _NearbyPlacesSheetState();
}

class _NearbyPlacesSheetState extends State<_NearbyPlacesSheet> {
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
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 8,
                children: _kPlaceTypes.map((t) {
                  final (id, label, icon) = t;
                  return ChoiceChip(
                    avatar: Icon(icon, size: 18),
                    label: Text(label),
                    selected: _type == id,
                    onSelected: (_) {
                      setState(() => _type = id);
                      _search();
                    },
                  );
                }).toList(),
              ),
            ),
            if (_canSearchAlongRoute)
              SwitchListTile(
                title: const Text('Search along the route'),
                value: _alongRoute,
                onChanged: (v) {
                  setState(() => _alongRoute = v);
                  _search();
                },
                dense: true,
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
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
                                const SizedBox(height: 12),
                                FilledButton(onPressed: _search, child: const Text('Try again')),
                              ],
                            ),
                          ),
                        )
                      : _places.isEmpty
                          ? const Center(child: Text('No places found nearby.'))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _places.length,
                              itemBuilder: (context, i) {
                                final place = _places[i];
                                return ListTile(
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(place.name),
                                  onTap: () => _openDetails(place),
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
