import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/trip.dart';
import '../../data/providers/repository_providers.dart';
import '../social/group_detail_screen.dart';
import '../social/social_providers.dart';
import '../trip/trip_detail_screen.dart';
import '../trip/trip_providers.dart';
import 'notifications_providers.dart';

/// The notification inbox: everything the server pushed to this account, kept
/// as a durable feed (`notifications`) since OS pushes aren't retained.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    return BrandScaffold(
      header: BrandHeader(
        title: 'Notifications',
        onBack: () => Navigator.of(context).maybePop(),
        actionIcon: Icons.done_all_rounded,
        actionTooltip: 'Mark all as read',
        onAction: unread == 0 ? null : () => _markAllRead(context, ref),
      ),
      child: feedAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: BrandEmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications yet',
                message:
                    'Trip invites, chat messages, group activity and convoy alerts show up here.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              ref.invalidate(unreadNotificationsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(
                top: BrandSpace.md,
                bottom: BrandSpace.xl,
              ),
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const SizedBox(height: BrandSpace.sm),
                  _NotificationCard(
                    notification: item,
                    onTap: () => _open(context, ref, item),
                    onDelete: () => _delete(context, ref, item),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorRetry(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(notificationsFeedRepositoryProvider).markAllRead();
      _refresh(ref);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete notification?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(notificationsFeedRepositoryProvider)
          .deleteNotification(item.id);
      _refresh(ref);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Marks the notification read, then opens whatever it refers to.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
  ) async {
    if (item.isUnread) {
      try {
        await ref.read(notificationsFeedRepositoryProvider).markRead(item.id);
        _refresh(ref);
      } catch (_) {
        // A failed read-receipt must not block navigation.
      }
    }
    if (!context.mounted) return;

    final tripId = item.tripId;
    final groupId = item.groupId;
    if (tripId != null) {
      await _openTrip(context, ref, tripId);
    } else if (groupId != null) {
      await _openGroup(context, ref, groupId);
    }
  }

  Future<void> _openTrip(
    BuildContext context,
    WidgetRef ref,
    String tripId,
  ) async {
    Trip? trip;
    try {
      final trips = await ref.read(myTripsProvider.future);
      for (final t in trips) {
        if (t.id == tripId) {
          trip = t;
          break;
        }
      }
    } catch (_) {
      // Fall through to the "open Trips" hint below.
    }
    if (!context.mounted) return;
    if (trip == null) {
      showAppToast(context, 'Open Trips to view this.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip!)),
    );
  }

  Future<void> _openGroup(
    BuildContext context,
    WidgetRef ref,
    String groupId,
  ) async {
    try {
      final group = await ref.read(groupProvider(groupId).future);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
      );
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, "You're no longer in that group.");
      }
    }
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: BrandSpace.lg),
        decoration: BoxDecoration(
          color: BrandColors.errorContainer,
          borderRadius: BrandRadii.cardRadius,
        ),
        child: Icon(Icons.delete_outline_rounded, color: BrandColors.error),
      ),
      confirmDismiss: (_) async {
        onDelete();
        // The list is rebuilt from the provider once the delete lands.
        return false;
      },
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: BrandCard(
          padding: const EdgeInsets.all(BrandSpace.md),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: _iconBackground(notification.kind),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon(notification.kind),
                size: 20,
                color: _iconColor(notification.kind),
              ),
            ),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: BrandText.weight(
                            BrandText.titleSm,
                            700,
                          ).copyWith(color: BrandColors.textHeadline),
                        ),
                      ),
                      if (unread)
                        Container(
                          height: 8,
                          width: 8,
                          decoration: BoxDecoration(
                            color: BrandColors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (notification.body != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textBody,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(notification.createdAt),
                    style: BrandText.labelSm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _icon(String kind) => switch (kind) {
  'trip_invites' => Icons.route_rounded,
  'chat_messages' => Icons.chat_bubble_rounded,
  'trip_updates' => Icons.play_circle_rounded,
  'group_invites' => Icons.groups_rounded,
  'convoy_alerts' => Icons.sos_rounded,
  _ => Icons.notifications_rounded,
};

Color _iconColor(String kind) => switch (kind) {
  'convoy_alerts' => BrandColors.error,
  _ => BrandColors.primary,
};

Color _iconBackground(String kind) => switch (kind) {
  'convoy_alerts' => BrandColors.errorContainer,
  _ => BrandColors.secondaryFixed.withValues(alpha: 0.5),
};

/// Compact relative age: "just now", "5m", "3h", "2d", then an absolute date.
String _relativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat.yMMMd().format(time);
}
