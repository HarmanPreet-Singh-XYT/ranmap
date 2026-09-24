import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/place_details.dart';
import '../../data/models/route_option.dart';
import '../../data/services/google_maps_api_service.dart';

/// Shows richer metadata for [place] (rating, review count, opening hours) —
/// fetched from Google on demand, since the search results themselves come
/// from Mapbox. Pops `true` if the user chooses to pin it on the map.
Future<bool?> showPlaceDetailsSheet(BuildContext context, NearbyPlace place) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<PlaceDetails>(
          future: _future,
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.data?.name ?? widget.place.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _buildBody(context, snapshot),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.place_rounded),
                    label: const Text('Pin on map'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<PlaceDetails> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snapshot.hasError) {
      // The place is still pinnable even when the detail lookup fails.
      return Text(
        friendlyError(snapshot.error!),
        style: const TextStyle(color: AppTheme.danger),
      );
    }

    final details = snapshot.data;
    if (details == null) return const SizedBox.shrink();

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details.ratingLabel != null)
          Row(
            children: [
              Text(details.ratingLabel!, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (details.priceLabel != null) ...[
                const SizedBox(width: 12),
                Text(details.priceLabel!, style: TextStyle(color: muted)),
              ],
              if (details.openNow != null) ...[
                const SizedBox(width: 12),
                Text(
                  details.openNow! ? 'Open now' : 'Closed',
                  style: TextStyle(color: details.openNow! ? AppTheme.success : muted),
                ),
              ],
            ],
          ),
        if (details.address != null) ...[
          const SizedBox(height: 8),
          Text(details.address!, style: TextStyle(color: muted)),
        ],
        if (details.weekdayHours.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final line in details.weekdayHours)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: TextStyle(color: muted, fontSize: 12)),
            ),
        ],
      ],
    );
  }
}
