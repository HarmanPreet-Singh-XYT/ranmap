import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../data/models/place_details.dart';
import '../../data/models/route_option.dart';
import '../../data/services/google_maps_api_service.dart';

/// Shows richer metadata for [place] (rating, review count, opening hours) —
/// fetched from Google on demand, since the search results themselves come
/// from Mapbox. Pops `true` if the user chooses to pin it on the map.
Future<bool?> showPlaceDetailsSheet(BuildContext context, NearbyPlace place) {
  return showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (_) => _PlaceDetailsSheet(place: place),
  );
}

class _PlaceDetailsSheet extends StatefulWidget {
  const _PlaceDetailsSheet({required this.place});

  final NearbyPlace place;

  @override
  State<_PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<_PlaceDetailsSheet> {
  late Future<PlaceDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = GoogleMapsApiService.placeDetails(widget.place);
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<PlaceDetails>(
          future: _future,
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.data?.name ?? widget.place.name,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.foreground),
                ),
                const SizedBox(height: 10),
                _buildBody(context, snapshot),
                const SizedBox(height: 20),
                FButton(
                  size: .lg,
                  onPress: () => Navigator.of(context).pop(true),
                  prefix: const Icon(Icons.place_rounded),
                  child: const Text('Pin on map'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<PlaceDetails> snapshot) {
    final c = NavColors.of(context);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: FCircularProgress()),
      );
    }
    if (snapshot.hasError) {
      // The place is still pinnable even when the detail lookup fails.
      return Text(
        friendlyError(snapshot.error!),
        style: TextStyle(color: c.destructive),
      );
    }

    final details = snapshot.data;
    if (details == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details.ratingLabel != null)
          Row(
            children: [
              Text(details.ratingLabel!, style: TextStyle(fontWeight: FontWeight.w600, color: c.foreground)),
              if (details.priceLabel != null) ...[
                const SizedBox(width: 12),
                Text(details.priceLabel!, style: TextStyle(color: c.mutedForeground)),
              ],
              if (details.openNow != null) ...[
                const SizedBox(width: 12),
                Text(
                  details.openNow! ? 'Open now' : 'Closed',
                  style: TextStyle(color: details.openNow! ? c.success : c.mutedForeground),
                ),
              ],
            ],
          ),
        if (details.address != null) ...[
          const SizedBox(height: 8),
          Text(details.address!, style: TextStyle(color: c.mutedForeground)),
        ],
        if (details.weekdayHours.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final line in details.weekdayHours)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: TextStyle(color: c.mutedForeground, fontSize: 12)),
            ),
        ],
      ],
    );
  }
}
