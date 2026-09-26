import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/group.dart';
import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/friend_repository.dart';
import '../../data/repositories/group_repository.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(),
);
final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(),
);

final friendsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(friendRepositoryProvider).friends(),
);

final incomingRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(friendRepositoryProvider).incomingRequests(),
    );

final outgoingRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(friendRepositoryProvider).outgoingRequests(),
    );

final usernameSearchProvider = FutureProvider.autoDispose
    .family<List<Profile>, String>((ref, query) async {
      if (query.trim().length < 2) return [];
      return ref
          .watch(profileRepositoryProvider)
          .searchByUsername(query.trim());
    });

final myGroupsProvider = FutureProvider.autoDispose<List<Group>>(
  (ref) => ref.watch(groupRepositoryProvider).myGroups(),
);

final groupMembersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, groupId) {
      return ref.watch(groupRepositoryProvider).membersFor(groupId);
    });
