import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/util/document_upload.dart';
import '../../core/util/image_upload.dart';
import '../models/user_document.dart';
import '../services/supabase_service.dart';

/// The user's private document wallet. Files live in the private `documents`
/// bucket under the owner's own folder (see 0030), and rows are owner-only.
class DocumentRepository {
  final _client = SupabaseService.client;

  static const _maxDocuments = 100;

  Future<List<UserDocument>> list() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('user_documents')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(_maxDocuments);
    return (rows as List)
        .map((r) => UserDocument.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a document image/PDF and records its metadata. On a metadata
  /// failure the uploaded object is removed so the bucket isn't orphaned.
  Future<UserDocument> upload({
    required String name,
    required String kind,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final uid = SupabaseService.currentUserId;
    final ext = fileExtension.toLowerCase();
    final validationError = documentUploadError(
      byteLength: bytes.length,
      extension: ext,
    );
    if (validationError != null) throw ImageUploadException(validationError);

    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage
        .from('documents')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: documentContentType(ext)),
        );

    try {
      final row = await _client
          .from('user_documents')
          .insert({
            'user_id': uid,
            'name': name,
            'kind': kind,
            'storage_path': path,
          })
          .select()
          .single();
      return UserDocument.fromJson(row);
    } catch (e) {
      await _client.storage.from('documents').remove([path]);
      rethrow;
    }
  }

  /// The file's bytes, fetched with the user's session (the bucket is private),
  /// so the app can render it in place rather than hand off a URL.
  Future<Uint8List> download(String storagePath) {
    return _client.storage.from('documents').download(storagePath);
  }

  /// A short-lived signed URL for the file (the bucket is private).
  Future<String> signedUrl(String storagePath, {int expiresInSeconds = 3600}) {
    return _client.storage
        .from('documents')
        .createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<void> delete({required String id, required String storagePath}) async {
    await _client.from('user_documents').delete().eq('id', id);
    try {
      await _client.storage.from('documents').remove([storagePath]);
    } catch (_) {
      // The row is gone; a leftover object is best-effort cleanup.
    }
  }
}
