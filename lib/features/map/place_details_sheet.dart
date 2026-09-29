import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../data/models/place_details.dart';
import '../../data/models/route_option.dart';
import '../../data/services/google_maps_api_service.dart';
import 'saved_place_providers.dart';

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

class _PlaceDetailsSheet extends ConsumerStatefulWidget {
  const _PlaceDetailsSheet({required this.place});

  final NearbyPlace place;

  @override
  ConsumerState<_PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends ConsumerState<_PlaceDetailsSheet> {
  late Future<PlaceDetails> _future;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _future = GoogleMapsApiService.placeDetails(widget.place);
  }

  /// Saves this place to the user's saved places, carrying its real
  /// coordinates — so a place found via search is bookmarkable directly,
  /// instead of only being pinnable for the current session.
  Future<void> _save(String name) async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      await ref.read(savedPlaceRepositoryProvider).createPlace(
            name: name,
            lat: widget.place.location.lat.toDouble(),
            lng: widget.place.location.lng.toDouble(),
          );
      ref.invalidate(savedPlacesProvider);
      if (!mounted) return;
      setState(() => _saved = true);
      showAppToast(context, 'Saved "$name" to your places.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandSheetSurface(
      child: FutureBuilder<PlaceDetails>(
        future: _future,
        builder: (context, snapshot) {
          final name = snapshot.data?.name ?? widget.place.name;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: BrandText.headlineMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
              const SizedBox(height: BrandSpace.sm),
              _buildBody(context, snapshot),
              const SizedBox(height: BrandSpace.lg),
              BrandPrimaryButton(
                label: 'Pin on map',
                leadingIcon: Icons.place_rounded,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: BrandSpace.sm),
              BrandSecondaryButton(
                label: _saved ? 'Saved to my places' : 'Save to my places',
                leading: Icon(
                  _saved
                      ? Icons.bookmark_added_rounded
                      : Icons.bookmark_add_outlined,
                  size: 20,
                  color: BrandColors.textHeadlineAlt,
                ),
                onPressed: (_saved || _saving) ? null : () => _save(name),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<PlaceDetails> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: BrandSpace.lg),
        child: Center(
          child: CircularProgressIndicator(color: BrandColors.primaryContainer),
        ),
      );
    }
    if (snapshot.hasError) {
      // The place is still pinnable even when the detail lookup fails.
      return Text(
        friendlyError(snapshot.error!),
        style: BrandText.bodyMd.copyWith(color: BrandColors.error),
      );
    }

    final details = snapshot.data;
    if (details == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details.ratingLabel != null)
          Wrap(
            spacing: BrandSpace.sm,
            runSpacing: BrandSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                details.ratingLabel!,
                style: BrandText.labelMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
              if (details.priceLabel != null)
                Text(
                  details.priceLabel!,
                  style: BrandText.labelMd.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              if (details.openNow != null)
                BrandPill(
                  label: details.openNow! ? 'Open now' : 'Closed',
                  background: details.openNow!
                      ? BrandColors.secondaryContainer
                      : BrandColors.surfaceContainer,
                  foreground: details.openNow!
                      ? BrandColors.onSecondaryFixedVariant
                      : BrandColors.textMuted,
                ),
            ],
          ),
        if (details.address != null) ...[
          const SizedBox(height: BrandSpace.sm),
          Text(
            details.address!,
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
        ],
        if (details.weekdayHours.isNotEmpty) ...[
          const SizedBox(height: BrandSpace.sm),
          for (final line in details.weekdayHours)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ),
        ],
      ],
    );
  }
}
