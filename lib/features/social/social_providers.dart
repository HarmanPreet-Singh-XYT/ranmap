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

/// A single profile by its exact handle (null when there's no such user). Used
/// to resolve a known handle — such as an invite link's inviter — without the
/// fuzzy search.
final profileByUsernameProvider = FutureProvider.autoDispose
    .family<Profile?, String>((ref, username) {
      return ref.watch(profileRepositoryProvider).fetchByUsername(username);
    });

final myGroupsProvider = FutureProvider.autoDispose<List<Group>>(
  (ref) => ref.watch(groupRepositoryProvider).myGroups(),
);

/// A single group's current row (RLS: members only). Watched by the detail
/// screen so renames / invite changes re-render without passing fresh state
/// down from the list.
final groupProvider = FutureProvider.autoDispose.family<Group, String>(
  (ref, groupId) => ref.watch(groupRepositoryProvider).fetchGroup(groupId),
);

final groupMembersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, groupId) {
      return ref.watch(groupRepositoryProvider).membersFor(groupId);
    });

/// The public preview of the group behind an invite code (null when the code
/// is unknown/stale), shown before the user commits to joining.
final groupInvitePreviewProvider = FutureProvider.autoDispose
    .family<GroupInvitePreview?, String>((ref, code) {
      return ref.watch(groupRepositoryProvider).invitePreview(code);
    });
