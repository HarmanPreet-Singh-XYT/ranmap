/// Shared validation for user-uploaded images (avatars, map photos). These are
/// UX-level guards (immediate, specific feedback) applied before an upload so a
/// huge or unexpected file never reaches Storage; the bucket policies remain
/// authoritative.
library;

/// Maximum size for a user-uploaded image.
const int kMaxImageUploadBytes = 5 * 1024 * 1024;

/// Thrown when an upload is rejected by local validation (bad type / too
/// large). Its [toString] is the user-facing message, so `friendlyError`
/// surfaces it directly.
class ImageUploadException implements Exception {
  const ImageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Image container formats the app is willing to upload.
const Set<String> kAllowedImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
};

const Map<String, String> _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// A picked filename's extension, lowercased and without the dot. Falls back to
/// `jpg` when the name has no usable extension.
String imageExtensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return 'jpg';
  return filename.substring(dot + 1).toLowerCase();
}

/// The MIME type for [extension], defaulting to a safe binary type.
String imageContentType(String extension) =>
    _mimeByExtension[extension.toLowerCase()] ?? 'application/octet-stream';

/// Validates an image about to be uploaded, returning a user-facing error or
/// null when it's acceptable. [extension] should come from [imageExtensionOf].
String? imageUploadError({
  required int byteLength,
  required String extension,
}) {
  if (!kAllowedImageExtensions.contains(extension.toLowerCase())) {
    return 'Unsupported image type — use a JPEG, PNG, WebP or HEIC photo.';
  }
  if (byteLength == 0) {
    return 'That photo looks empty — try another.';
  }
  if (byteLength > kMaxImageUploadBytes) {
    return 'That photo is too large (max 5 MB).';
  }
  return null;
}
