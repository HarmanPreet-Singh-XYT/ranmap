import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/saved_place.dart';
import 'saved_place_providers.dart';

/// A dedicated home for the places the user (or the AI copilot) has saved —
/// the list previously only appeared inside the map's no-convoy card, so it had
/// no durable, discoverable surface.
class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(savedPlacesProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Saved places',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: placesAsync.when(
        data: (places) {
          if (places.isEmpty) {
            return const Center(
              child: BrandEmptyState(
                icon: Icons.bookmark_border_rounded,
                title: 'No saved places yet',
                message:
                    'Tap a spot on the map and choose "Save this place", or ask the AI assistant to remember one. Your saved places collect here.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
            children: [
              BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(
                  children: [
                    for (final (i, place) in places.indexed) ...[
                      if (i > 0) const BrandRowDivider(),
                      _SavedPlaceRow(
                        place: place,
                        onDelete: () => _delete(context, ref, place),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorRetry(error: e, onRetry: () => ref.invalidate(savedPlacesProvider)),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SavedPlace place,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove saved place?',
      message: 'Remove "${place.name}" from your saved places?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(savedPlaceRepositoryProvider).deletePlace(place.id);
      ref.invalidate(savedPlacesProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({required this.place, required this.onDelete});

  final SavedPlace place;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final point = place.point;
    final subtitle = place.notes?.isNotEmpty == true
        ? place.notes
        : point != null
        ? '${point.lat.toStringAsFixed(4)}, ${point.lng.toStringAsFixed(4)}'
        : 'Name only — no location saved';

    return BrandListRow(
      icon: Icons.bookmark_rounded,
      iconColor: BrandColors.primary,
      title: place.name,
      subtitle: subtitle,
      showChevron: false,
      onTap: point == null ? null : () => _openDirections(context, point.lat, point.lng),
      trailing: BrandFieldAction(
        icon: Icons.delete_outline_rounded,
        color: BrandColors.error,
        semanticLabel: 'Delete saved place',
        onTap: onDelete,
      ),
    );
  }

  /// Hands coordinates off to the native Google Maps app for directions, the
  /// same hand-off the live-teammate sheet uses.
  Future<void> _openDirections(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        showAppToast(context, 'Could not open Google Maps.', error: true);
      }
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, 'Could not open Google Maps.', error: true);
      }
    }
  }
}
