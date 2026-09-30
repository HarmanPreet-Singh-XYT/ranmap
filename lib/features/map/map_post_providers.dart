import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/group.dart';
import '../../data/models/map_post.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/map_post_repository.dart';
import '../../data/services/supabase_service.dart';
import '../social/social_providers.dart';
import '../trip/trip_providers.dart';

final mapPostRepositoryProvider = Provider<MapPostRepository>(
  (ref) => MapPostRepository(),
);

final tripMapPostsProvider = FutureProvider.autoDispose
    .family<List<MapPost>, String>((ref, tripId) {
      return ref.watch(mapPostRepositoryProvider).postsForTrip(tripId);
    });

/// Photos shared with a group (via "Share to a group"), for the crew gallery.
final groupSharedPostsProvider = FutureProvider.autoDispose
    .family<List<MapPost>, String>((ref, groupId) {
      return ref.watch(mapPostRepositoryProvider).postsSharedWithGroup(groupId);
    });

/// Photos friends have shared directly with the current user.
final sharedWithMePostsProvider = FutureProvider.autoDispose<List<MapPost>>((
  ref,
) {
  return ref.watch(mapPostRepositoryProvider).postsSharedWithMe();
});

final mapPostSignedUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, storagePath) {
      return ref.watch(mapPostRepositoryProvider).signedUrl(storagePath);
    });

/// A photo in the library, with where it reached the user from.
class LibraryPhoto {
  const LibraryPhoto({
    required this.post,
    required this.isMine,
    this.groupNames = const {},
  });

  final MapPost post;
  final bool isMine;

  /// Groups this photo was shared to (searchable).
  final Set<String> groupNames;
}

/// Every photo the user can browse: their own pins, everyone's photos on trips
/// they're part of, photos shared to their groups, and photos friends sent them
/// directly — de-duplicated, newest first. Each source is explicit (never "all
/// visible"), so other people's *public* photos from unrelated trips don't
/// leak in; RLS still decides what a member may see within each source.
final allPhotosProvider = FutureProvider.autoDispose<List<LibraryPhoto>>((
  ref,
) async {
  final repo = ref.watch(mapPostRepositoryProvider);
  final me = SupabaseService.currentUser?.id;
  // Subscribe before any await, so the library refreshes with trips/groups.
  final tripsFuture = ref.watch(myTripsProvider.future);
  final groupsFuture = ref.watch(myGroupsProvider.future);

  // Own photos are the core of the library; let their failure surface.
  final mine = await repo.myPosts();

  // The rest are additive: one failing source mustn't hide the others.
  Future<T> soft<T>(Future<T> Function() load, T fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  final trips = await soft<List<Trip>>(() => tripsFuture, const []);
  final groups = await soft<List<Group>>(() => groupsFuture, const []);
  final groupNameById = {for (final g in groups) g.id: g.name};

  final fromTrips = await soft(
    () => repo.postsForTrips([for (final t in trips) t.id]),
    const <MapPost>[],
  );
  final fromGroups = await soft(
    () => repo.postsSharedWithGroups(groupNameById.keys.toList()),
    const <({String groupId, MapPost post})>[],
  );
  final direct = await soft(repo.postsSharedWithMe, const <MapPost>[]);

  final posts = <String, MapPost>{};
  final groupNames = <String, Set<String>>{};
  for (final p in [...mine, ...fromTrips, ...direct]) {
    posts[p.id] = p;
  }
  for (final entry in fromGroups) {
    posts[entry.post.id] = entry.post;
    final name = groupNameById[entry.groupId];
    if (name != null) {
      groupNames.putIfAbsent(entry.post.id, () => {}).add(name);
    }
  }

  return [
    for (final p in posts.values)
      LibraryPhoto(
        post: p,
        isMine: p.userId == me,
        groupNames: groupNames[p.id] ?? const {},
      ),
  ]..sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));
});
