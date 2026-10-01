import {
  ALLOWED_IMAGE_MIME_TYPES,
  extensionOf,
  imageMimeForExtension,
} from "./image";

/** The `documents` bucket accepts PDFs as well as photos (0055). */
export const ALLOWED_DOCUMENT_MIME_TYPES: readonly string[] = [
  ...ALLOWED_IMAGE_MIME_TYPES,
  "application/pdf",
];

/**
 * Matches the bucket's `file_size_limit` (0055) — more generous than the photo
 * buckets, because a multi-page scan legitimately is.
 */
export const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;

export const UNSUPPORTED_DOCUMENT_MESSAGE =
  "Unsupported file — use a PDF or a JPEG, PNG, WebP, GIF or HEIC image.";

export const DOCUMENT_TOO_LARGE_MESSAGE = "That file is over 10 MB.";

/**
 * The MIME to upload [file] as. Browsers report nothing for some files, so fall
 * back to the extension rather than to `application/octet-stream` — which the
 * bucket refuses. Returns "" when the file can't be identified.
 */
export function documentMimeOf(file: File): string {
  const type = (file.type || "").toLowerCase();
  if (type === "image/jpg") return "image/jpeg";
  if (type) return type;
  const extension = extensionOf(file.name);
  if (extension === "pdf") return "application/pdf";
  return imageMimeForExtension(extension) ?? "";
}

export function isAllowedDocument(file: File): boolean {
  return ALLOWED_DOCUMENT_MIME_TYPES.includes(documentMimeOf(file));
}
