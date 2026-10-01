import '../../../core/util/geo_distance.dart';
import '../../../data/models/map_post.dart';

/// Groups photo pins that sit within [radiusMeters] of a stack's anchor into one
/// pin that then carries a count, instead of several pins hiding behind each
/// other. Clustering by real distance — rather than rounded coordinates — keeps
/// two close-together photos in one stack wherever the rounding boundary would
/// otherwise fall.
///
/// Each stack is sorted oldest-first, so the swipe order matches the order the
/// photos were taken, and a stack's first post is its anchor.
List<List<MapPost>> stackPhotoPins(
  List<MapPost> posts, {
  required double radiusMeters,
}) {
  final stacks = <List<MapPost>>[];
  for (final post in posts) {
    List<MapPost>? stack;
    for (final candidate in stacks) {
      final anchor = candidate.first;
      if (haversineMeters(anchor.lat, anchor.lng, post.lat, post.lng) <=
          radiusMeters) {
        stack = candidate;
        break;
      }
    }
    if (stack == null) {
      stack = <MapPost>[];
      stacks.add(stack);
    }
    stack.add(post);
  }
  for (final stack in stacks) {
    stack.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  return stacks;
}
