import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import 'notifications_providers.dart';
import 'notifications_screen.dart';

/// The app-bar bell: opens the notification inbox and badges the unread count.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      child: Tooltip(
        message: 'Notifications',
        child: GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            // Refresh the badge for anything read/cleared while in the inbox.
            ref.invalidate(unreadNotificationsProvider);
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 44,
            width: 44,
            child: Center(
              child: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                backgroundColor: BrandColors.error,
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: BrandColors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
