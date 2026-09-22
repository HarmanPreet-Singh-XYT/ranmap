import 'dart:typed_data';

import '../models/map_post.dart';
import '../services/supabase_service.dart';

/// Photos pinned to the map (`map_posts`, backed by files in the private
/// `map-media` storage bucket). Storage RLS requires every object path to be
/// prefixed with the uploader's own auth.uid() folder (see
/// 0002_rls_hardening.sql), so uploads always go under `<uid>/...`.
class MapPostRepository {
  final _client = SupabaseService.client;

  Future<MapPost> createPost({
    required Uint8List imageBytes,
    required String fileExtension,
    required double lat,
    required double lng,
    String? caption,
    String? tripId,
    String visibility = 'group',
  }) async {
    final uid = SupabaseService.currentUserId;
    final storagePath =
        '$uid/${DateTime.now().microsecondsSinceEpoch}.$fileExtension';

    await _client.storage.from('map-media').uploadBinary(storagePath, imageBytes);

    final row = await _client
        .from('map_posts')
        .insert({
          'trip_id': tripId,
          'user_id': uid,
          'point': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
          'storage_path': storagePath,
          'caption': caption,
          'visibility': visibility,
        })
        .select('*, profiles(username)')
        .single();
    return MapPost.fromJson(row);
  }

  /// Posts visible to the current user for a trip (RLS already restricts
  /// this to owner/public/group-participant/explicitly-shared — see
  /// can_view_map_post in 0002_rls_hardening.sql).
  Future<List<MapPost>> postsForTrip(String tripId) async {
    final rows = await _client
        .from('map_posts')
        .select('*, profiles(username)')
        .eq('trip_id', tripId)
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List).map((r) => MapPost.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// A signed URL for the post's photo (the bucket is private).
  Future<String> signedUrl(String storagePath, {int expiresInSeconds = 3600}) {
    return _client.storage.from('map-media').createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<void> shareWithGroup({required String postId, required String groupId}) async {
    await _client.from('map_post_shares').insert({
      'post_id': postId,
      'shared_with_group': groupId,
    });
  }

  Future<void> shareWithUser({required String postId, required String userId}) async {
    await _client.from('map_post_shares').insert({
      'post_id': postId,
      'shared_with_user': userId,
    });
  }

  Future<void> deletePost(String postId) async {
    await _client.from('map_posts').delete().eq('id', postId);
  }
}
