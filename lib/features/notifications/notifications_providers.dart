import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_notification.dart';
import '../../data/providers/repository_providers.dart';

/// The current user's notification feed, newest first.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationsFeedRepositoryProvider).fetchNotifications(),
);

/// Unread count for the bell badge. There's no realtime subscription on the
/// feed, so this refreshes on a slow poll as well as being invalidated by the
/// read/delete actions on the Notifications screen.
final unreadNotificationsProvider = StreamProvider.autoDispose<int>((ref) async* {
  final repo = ref.watch(notificationsFeedRepositoryProvider);
  Future<int> read() async {
    try {
      return await repo.unreadCount();
    } catch (_) {
      // A transient failure shouldn't flash a wrong badge; report none.
      return 0;
    }
  }

  yield await read();
  await for (final _ in Stream.periodic(const Duration(seconds: 60))) {
    yield await read();
  }
});
