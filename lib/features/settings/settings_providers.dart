import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/auth_state_provider.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/notification_repository.dart';

/// The signed-in user's notification preferences (server-backed, so the push
/// sender respects them).
final notificationPreferencesProvider = FutureProvider<NotificationPreferences>(
  (ref) {
    ref.watch(currentUserIdProvider);
    return ref.watch(notificationRepositoryProvider).fetch();
  },
);
