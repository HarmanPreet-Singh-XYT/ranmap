import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/map_post.dart';
import '../../data/repositories/map_post_repository.dart';

final mapPostRepositoryProvider = Provider<MapPostRepository>((ref) => MapPostRepository());

final tripMapPostsProvider =
    FutureProvider.autoDispose.family<List<MapPost>, String>((ref, tripId) {
  return ref.watch(mapPostRepositoryProvider).postsForTrip(tripId);
});

final mapPostSignedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, storagePath) {
  return ref.watch(mapPostRepositoryProvider).signedUrl(storagePath);
});
