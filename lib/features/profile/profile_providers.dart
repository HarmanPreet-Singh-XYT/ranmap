import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/phone_repository.dart';
import '../../data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository());
final phoneRepositoryProvider = Provider<PhoneRepository>((ref) => PhoneRepository());

/// The current user's private fields (phone_number / socials /
/// phone_verified), fetched through the `my_private_profile` RPC.
final myPrivateProfileProvider = FutureProvider.autoDispose<
    ({String? phoneNumber, Map<String, String> socials, bool phoneVerified})>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyPrivate();
});
