import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../map/map_navigation.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/trip.dart';
import '../map/map_post_viewer_sheet.dart';
import '../trip/trip_detail_screen.dart';
import '../trip/trip_providers.dart';
import 'chat_providers.dart';

/// The body of a photo / location / trip chat message: a compact, tappable card
/// instead of raw text. [color] is the bubble's foreground colour.
class RichMessageBody extends ConsumerWidget {
  const RichMessageBody({
    super.key,
    required this.message,
    required this.color,
  });

  final ChatMessage message;
  final Color color;

  Future<void> _openPhotos(BuildContext context, WidgetRef ref) async {
    try {
      final posts = await ref
          .read(chatRepositoryProvider)
          .postsByIds(message.photoPostIds);
      if (!context.mounted) return;
      if (posts.isEmpty) {
        showAppToast(
          context,
          'That photo is no longer available.',
          error: true,
        );
        return;
      }
      await showMapPostViewerSheet(context, posts.first, stack: posts);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  void _openLocation(BuildContext context, WidgetRef ref) {
    final lat = message.payloadLat;
    final lng = message.payloadLng;
    if (lat == null || lng == null) return;
    navigateInApp(
      context,
      ref,
      name: message.payloadName ?? 'Shared location',
      lat: lat,
      lng: lng,
    );
  }

  void _openTrip(BuildContext context, WidgetRef ref) {
    final id = message.payloadTripId;
    final trips = ref.read(myTripsProvider).valueOrNull ?? const <Trip>[];
    final trip = trips.where((t) => t.id == id).firstOrNull;
    if (trip == null) {
      showAppToast(context, "You're not on this trip — ask to be invited.");
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) = switch (message.kind) {
      ChatMessageKind.photo => (
        Icons.push_pin_rounded,
        message.photoPostIds.length > 1
            ? 'Pinned images (${message.photoPostIds.length})'
            : 'Pinned image',
        'Tap to view',
        () => _openPhotos(context, ref),
      ),
      ChatMessageKind.location => (
        Icons.place_rounded,
        message.payloadName ?? 'Shared location',
        'Tap for directions',
        () => _openLocation(context, ref),
      ),
      ChatMessageKind.trip => (
        Icons.directions_car_filled_rounded,
        message.payloadTripTitle ?? 'Trip',
        'Tap to open trip',
        () => _openTrip(context, ref),
      ),
      ChatMessageKind.text => (
        Icons.chat_bubble_outline_rounded,
        message.body ?? '',
        '',
        () {},
      ),
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.weight(
                    BrandText.bodyMd,
                    700,
                  ).copyWith(color: color),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: BrandText.bodySm.copyWith(
                      color: color.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
