import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/group.dart';
import '../../data/models/person.dart';
import '../../data/models/trip.dart';
import '../trip/trip_providers.dart';
import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/friend_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/moderation_repository.dart';
import '../../data/repositories/people_repository.dart';

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(),
);
final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(),
);
final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(),
);

/// Everyone the user shares a context with, in one query — the People screen's
/// source. See `people_around_me()` (0050).
final peopleAroundMeProvider = FutureProvider.autoDispose<List<Person>>(
  (ref) => ref.watch(peopleRepositoryProvider).aroundMe(),
);
final moderationRepositoryProvider = Provider<ModerationRepository>(
  (ref) => ModerationRepository(),
);

/// Accounts the current user has blocked, newest first.
final blockedUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(moderationRepositoryProvider).blockedUsers(),
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

/// Group invitations waiting on an answer from me.
final groupInvitesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(groupRepositoryProvider).myInvites(),
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

/// Another user's public profile (null when they don't exist).
final publicProfileProvider = FutureProvider.autoDispose
    .family<Profile?, String>(
      (ref, userId) => ref.watch(profileRepositoryProvider).fetchById(userId),
    );

/// The friendship row between the viewer and [userId] (any status), or null.
final friendshipWithProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>(
      (ref, userId) => ref.watch(friendRepositoryProvider).friendshipWith(userId),
    );

/// Groups both the viewer and [userId] are active members of.
final commonGroupsProvider = FutureProvider.autoDispose
    .family<List<Group>, String>((ref, userId) async {
      final mine = await ref.watch(myGroupsProvider.future);
      final theirs = await ref
          .watch(profileRepositoryProvider)
          .activeGroupIdsOf(userId, [for (final g in mine) g.id]);
      return [
        for (final g in mine)
          if (theirs.contains(g.id)) g,
      ];
    });

/// Trips both the viewer and [userId] are on.
final commonTripsProvider = FutureProvider.autoDispose
    .family<List<Trip>, String>((ref, userId) async {
      final mine = await ref.watch(myTripsProvider.future);
      final theirs = await ref
          .watch(profileRepositoryProvider)
          .tripIdsOf(userId, [for (final t in mine) t.id]);
      return [
        for (final t in mine)
          if (theirs.contains(t.id)) t,
      ];
    });
