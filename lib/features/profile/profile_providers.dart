import 'package:flutter_riverpod/flutter_riverpod.dart';

// Repository providers (profile/phone) live in the data layer; re-exported so
// existing importers keep working.
import '../../data/providers/repository_providers.dart';

export '../../data/providers/repository_providers.dart';

/// The current user's private fields (phone_number / socials /
/// phone_verified), fetched through the `my_private_profile` RPC.
final myPrivateProfileProvider =
    FutureProvider.autoDispose<
      ({
        String? phoneNumber,
        Map<String, String> socials,
        bool phoneVerified,
        bool dmFromStrangers,
      })
    >((ref) {
      return ref.watch(profileRepositoryProvider).fetchMyPrivate();
    });
