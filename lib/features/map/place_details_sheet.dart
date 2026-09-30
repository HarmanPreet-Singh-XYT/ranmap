import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/backend_client.dart';
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
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'saved_place_providers.dart';

/// What the user chose in the details sheet.
enum PlaceDetailsAction {
  /// Pin the place on the map for this session.
  pin,

  /// Get in-app directions to the place.
  directions,
}

/// Shows richer metadata for [place] (photos, contact info, rating, opening
/// hours) — fetched from Google on demand, since the search results themselves
/// come from Mapbox. Pops the chosen [PlaceDetailsAction], or null if dismissed.
Future<PlaceDetailsAction?> showPlaceDetailsSheet(
  BuildContext context,
  NearbyPlace place,
) {
  return showFSheet<PlaceDetailsAction>(
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
      await ref
          .read(savedPlaceRepositoryProvider)
          .createPlace(
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

  Future<void> _open(String url, {bool external = true}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(
      uri,
      mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault,
    );
    if (!ok && mounted) showAppToast(context, 'Could not open that link.', error: true);
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
                label: 'Directions',
                leadingIcon: Icons.directions_rounded,
                onPressed: () =>
                    Navigator.of(context).pop(PlaceDetailsAction.directions),
              ),
              const SizedBox(height: BrandSpace.sm),
              BrandSecondaryButton(
                label: 'Pin on map',
                leading: Icon(
                  Icons.place_outlined,
                  size: 20,
                  color: BrandColors.textHeadlineAlt,
                ),
                onPressed: () =>
                    Navigator.of(context).pop(PlaceDetailsAction.pin),
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
      // The place is still routable/pinnable even when the lookup fails.
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
        if (details.photos.isNotEmpty) ...[
          // Google bills per photo, so the strip is a Pro feature; free users
          // see a teaser instead of firing any image requests.
          if (ref.watch(isProProvider))
            _photoStrip(details.photos)
          else
            _lockedPhotos(context, details.photos.length),
          const SizedBox(height: BrandSpace.sm),
        ],
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
        if (details.phone != null && _phoneUri(details.phone!) != null) ...[
          const SizedBox(height: BrandSpace.sm),
          _contactRow(
            Icons.phone_outlined,
            details.phone!,
            () => _open(_phoneUri(details.phone!)!, external: false),
          ),
        ],
        if (details.website != null) ...[
          const SizedBox(height: BrandSpace.xs),
          _contactRow(
            Icons.language_rounded,
            details.website!,
            () => _open(details.website!),
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
        // Google's Places terms require attribution wherever its data is shown.
        const SizedBox(height: BrandSpace.sm),
        Text(
          'Powered by Google',
          style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
        ),
      ],
    );
  }

  /// A `tel:` URI with the display formatting stripped — Google returns numbers
  /// like "(415) 397-8880", which some platforms reject verbatim.
  String? _phoneUri(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits.isEmpty ? null : 'tel:$digits';
  }

  /// Free-tier stand-in for the photo strip — a tappable upsell, so we never
  /// spend a Google Place Photos charge on a non-subscriber.
  Widget _lockedPhotos(BuildContext context, int count) {
    final noun = count == 1 ? 'photo' : 'photos';
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.sm,
      ),
      child: InkWell(
        borderRadius: BrandRadii.podRadius,
        onTap: () => showPaywall(context, feature: PremiumFeature.placePhotos),
        child: Row(
          children: [
            Icon(Icons.photo_library_outlined, color: BrandColors.primary),
            const SizedBox(width: BrandSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'See $count $noun of this place',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  Text(
                    'Ranmap Pro',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: BrandColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoStrip(List<PlacePhoto> photos) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: BrandSpace.sm),
        itemBuilder: (context, i) {
          final photo = photos[i];
          return GestureDetector(
            onTap: () => _openPhoto(photo),
            child: ClipRRect(
              borderRadius: BrandRadii.cardRadius,
              child: SizedBox(
                width: 210,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: GoogleMapsApiService.placePhotoUrl(photo.name),
                      httpHeaders: BackendClient.authHeadersOrNull(),
                      cacheKey: photo.name,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: BrandColors.surfaceContainer),
                      errorWidget: (_, _, _) => Container(
                        color: BrandColors.surfaceContainer,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: BrandColors.textMuted,
                        ),
                      ),
                    ),
                    // Google requires author attribution where a photo is shown.
                    if (photo.author != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Photo: ${photo.author}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrandText.labelSm.copyWith(color: Colors.white),
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

  /// Full-screen, zoomable view of one photo — Google's per-photo charge means
  /// the strip only loads thumbnails; the full image loads on tap.
  void _openPhoto(PlacePhoto photo) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: GoogleMapsApiService.placePhotoUrl(photo.name, width: 1200),
            httpHeaders: BackendClient.authHeadersOrNull(),
            cacheKey: '${photo.name}@1200',
            fit: BoxFit.contain,
            placeholder: (_, _) => const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, _, _) => const SizedBox(
              height: 260,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BrandRadii.pill,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: BrandColors.primary),
            const SizedBox(width: BrandSpace.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
