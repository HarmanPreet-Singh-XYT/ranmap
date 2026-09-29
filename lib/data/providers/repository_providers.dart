import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/account_repository.dart';
import '../repositories/avatar_repository.dart';
import '../repositories/convoy_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/notifications_feed_repository.dart';
import '../repositories/phone_repository.dart';
import '../repositories/premium_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/usage_repository.dart';
import '../repositories/weather_repository.dart';

/// Repository providers live in the data layer so both core (router/auth) and
/// features can depend on them without a feature layer importing another
/// feature. Screens and other providers should read these instead of
/// constructing a repository directly.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(),
);
final phoneRepositoryProvider = Provider<PhoneRepository>(
  (ref) => PhoneRepository(),
);
final premiumRepositoryProvider = Provider<PremiumRepository>(
  (ref) => PremiumRepository(),
);
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => const AccountRepository(),
);
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);
final notificationsFeedRepositoryProvider = Provider<NotificationsFeedRepository>(
  (ref) => NotificationsFeedRepository(),
);
final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => AvatarRepository(),
);
final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => const UsageRepository(),
);
final convoyRepositoryProvider = Provider<ConvoyRepository>(
  (ref) => ConvoyRepository(),
);
final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => WeatherRepository(),
);
