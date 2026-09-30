import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/defaults.dart';
import '../../core/util/image_upload.dart';
import '../models/map_post.dart';
import '../models/trip.dart';
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
    String visibility = kDefaultMapPostVisibility,
  }) async {
    final uid = SupabaseService.currentUserId;
    final extension = fileExtension.toLowerCase();
    final validationError = imageUploadError(
      byteLength: imageBytes.length,
      extension: extension,
    );
    if (validationError != null) throw ImageUploadException(validationError);

    final storagePath =
        '$uid/${DateTime.now().microsecondsSinceEpoch}.$extension';

    await _client.storage
        .from('map-media')
        .uploadBinary(
          storagePath,
          imageBytes,
          fileOptions: FileOptions(contentType: imageContentType(extension)),
        );

    try {
      final row = await _client
          .from('map_posts')
          .insert({
            'trip_id': tripId,
            'user_id': uid,
            'point': LatLngPoint(lat, lng).toEwkt(),
            'storage_path': storagePath,
            'caption': caption,
            'visibility': visibility,
          })
          .select('*, profiles(username)')
          .single();
      return MapPost.fromJson(row);
    } catch (e) {
      // Don't orphan the uploaded object when the row is rejected (the free
      // photo cap trigger, an RLS denial, …).
      await _client.storage.from('map-media').remove([storagePath]);
      rethrow;
    }
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
    return (rows as List)
        .map((r) => MapPost.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Photos other members have shared with [groupId] (via [shareWithGroup]).
  /// RLS already restricts this to groups the caller belongs to.
  Future<List<MapPost>> postsSharedWithGroup(String groupId) async {
    final rows = await _client
        .from('map_post_shares')
        .select('created_at, map_posts(*, profiles(username))')
        .eq('shared_with_group', groupId)
        .order('created_at', ascending: false)
        .limit(200);
    final posts = <MapPost>[];
    for (final raw in rows as List) {
      final post = (raw as Map<String, dynamic>)['map_posts'];
      if (post is Map<String, dynamic>) posts.add(MapPost.fromJson(post));
    }
    return posts;
  }

  /// Every photo the current user pinned, across all trips, newest first.
  Future<List<MapPost>> myPosts() async {
    final rows = await _client
        .from('map_posts')
        .select('*, profiles(username)')
        .eq('user_id', SupabaseService.currentUserId)
        .order('created_at', ascending: false)
        .limit(500);
    final posts = <MapPost>[];
    for (final row in rows as List) {
      // One undecodable row must not hide the whole library.
      try {
        posts.add(MapPost.fromJson(row as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return posts;
  }

  /// Photos pinned to any of [tripIds], by anyone on those trips. RLS decides
  /// which of other members' photos the caller may see (their `group` and
  /// `public` ones, not their `private` ones), so this never widens access.
  Future<List<MapPost>> postsForTrips(List<String> tripIds) async {
    if (tripIds.isEmpty) return const [];
    final posts = <MapPost>[];
    // Chunked so a long trip history can't overflow the request URL.
    for (var i = 0; i < tripIds.length; i += 50) {
      final chunk = tripIds.sublist(i, i + 50 > tripIds.length ? tripIds.length : i + 50);
      final rows = await _client
          .from('map_posts')
          .select('*, profiles(username)')
          .inFilter('trip_id', chunk)
          .order('created_at', ascending: false)
          .limit(500);
      for (final row in rows as List) {
        try {
          posts.add(MapPost.fromJson(row as Map<String, dynamic>));
        } catch (_) {
          continue;
        }
      }
    }
    return posts;
  }

  /// Photos shared with any of [groupIds], each paired with the group it was
  /// shared to (a photo shared to two groups appears twice, once per group).
  Future<List<({String groupId, MapPost post})>> postsSharedWithGroups(
    List<String> groupIds,
  ) async {
    if (groupIds.isEmpty) return const [];
    final rows = await _client
        .from('map_post_shares')
        .select('shared_with_group, map_posts(*, profiles(username))')
        .inFilter('shared_with_group', groupIds)
        .order('created_at', ascending: false)
        .limit(500);
    final out = <({String groupId, MapPost post})>[];
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      final post = row['map_posts'];
      final groupId = row['shared_with_group'];
      if (post is! Map<String, dynamic> || groupId is! String) continue;
      try {
        out.add((groupId: groupId, post: MapPost.fromJson(post)));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Photos friends have shared directly with the current user (via
  /// [shareWithUser]).
  Future<List<MapPost>> postsSharedWithMe() async {
    final rows = await _client
        .from('map_post_shares')
        .select('created_at, map_posts(*, profiles(username))')
        .eq('shared_with_user', SupabaseService.currentUserId)
        .order('created_at', ascending: false)
        .limit(200);
    final posts = <MapPost>[];
    for (final raw in rows as List) {
      final post = (raw as Map<String, dynamic>)['map_posts'];
      if (post is Map<String, dynamic>) posts.add(MapPost.fromJson(post));
    }
    return posts;
  }

  /// A signed URL for the post's photo (the bucket is private).
  Future<String> signedUrl(String storagePath, {int expiresInSeconds = 3600}) {
    return _client.storage
        .from('map-media')
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<void> shareWithGroup({
    required String postId,
    required String groupId,
  }) async {
    await _client.from('map_post_shares').insert({
      'post_id': postId,
      'shared_with_group': groupId,
    });
  }

  Future<void> shareWithUser({
    required String postId,
    required String userId,
  }) async {
    await _client.from('map_post_shares').insert({
      'post_id': postId,
      'shared_with_user': userId,
    });
  }

  /// Deletes the post and its backing storage object, so the private bucket
  /// doesn't accumulate files nothing references.
  Future<void> deletePost(String postId) async {
    final removed = await _client
        .from('map_posts')
        .delete()
        .eq('id', postId)
        .select('storage_path');
    final paths = (removed as List)
        .map((row) => (row as Map<String, dynamic>)['storage_path'])
        .whereType<String>()
        .toList();
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from('map-media').remove(paths);
      } catch (_) {
        // The row is gone either way; a leftover file is best-effort cleanup.
      }
    }
  }
}
