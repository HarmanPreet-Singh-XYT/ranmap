/// Shared validation for wallet uploads. The private `documents` bucket holds
/// scans *and* PDFs (0055), which is why this is separate from the image rules
/// in `image_upload.dart` — and why the ceiling is larger: a multi-page scan
/// legitimately is.
///
/// Mirrors the web's allow-list in `web-app/lib/data/document.ts`. These are
/// UX-level guards; the bucket is authoritative.
library;

import 'image_upload.dart';

/// Extensions the wallet accepts: every image the app can upload, plus PDF.
const Set<String> kAllowedDocumentExtensions = {
  ...kAllowedImageExtensions,
  'pdf',
};

/// Maximum size for a wallet upload. Matches the bucket's `file_size_limit`.
const int kMaxDocumentUploadBytes = 10 * 1024 * 1024;

/// A picked document's extension, lowercased and without the dot. Falls back to
/// `pdf`: a file that arrives from the document picker with no extension is one
/// of those, not a photo.
String documentExtensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return 'pdf';
  return filename.substring(dot + 1).toLowerCase();
}

/// The MIME type for [extension] — PDF, an image, or a safe binary fallback.
String documentContentType(String extension) =>
    extension.toLowerCase() == 'pdf'
    ? 'application/pdf'
    : imageContentType(extension);

/// Validates a document about to be uploaded, returning a user-facing error or
/// null when it's acceptable. [extension] should come from
/// [documentExtensionOf].
String? documentUploadError({
  required int byteLength,
  required String extension,
}) {
  if (!kAllowedDocumentExtensions.contains(extension.toLowerCase())) {
    return 'Unsupported file — use a PDF or a JPEG, PNG, WebP, GIF or HEIC image.';
  }
  if (byteLength == 0) {
    return 'That file looks empty — try another.';
  }
  if (byteLength > kMaxDocumentUploadBytes) {
    return 'That file is over 10 MB.';
  }
  return null;
}
