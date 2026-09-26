import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/util/image_upload.dart';
import '../services/supabase_service.dart';

/// Uploaded profile pictures, stored in the public `avatars` bucket.
///
/// Storage RLS requires every object path to be prefixed with the uploader's
/// own auth.uid() folder (see 0002_rls_hardening.sql), so uploads always go
/// under `<uid>/...`.
class AvatarRepository {
  final _client = SupabaseService.client;

  /// Uploads [bytes] and returns the storage path (not the `avatar_id` — wrap
  /// it with `customAvatarId`). Rejects an unexpected extension or an oversized
  /// file before it reaches Storage.
  Future<String> upload({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final extension = fileExtension.toLowerCase();
    final validationError = imageUploadError(
      byteLength: bytes.length,
      extension: extension,
    );
    if (validationError != null) throw ImageUploadException(validationError);

    final uid = SupabaseService.currentUserId;
    final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage.from('avatars').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: imageContentType(extension)),
    );
    return path;
  }

  /// Best-effort removal, used when replacing or clearing a photo. A leftover
  /// file is harmless, so cleanup never fails the caller.
  Future<void> remove(String storagePath) async {
    try {
      await _client.storage.from('avatars').remove([storagePath]);
    } catch (_) {
      // Ignore: the profile no longer references it either way.
    }
  }
}
