/**
 * The image types the `map-media` and `avatars` buckets accept — their
 * `allowed_mime_types`, set by 0054/0055. Mirrors the mobile allow-list
 * (`lib/core/util/image_upload.dart`), so a file refused here would have been
 * refused by Storage anyway — just with a vaguer message.
 */
export const ALLOWED_IMAGE_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
  "image/heic",
  "image/heif",
] as const;

const IMAGE_MIME_BY_EXTENSION: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  heic: "image/heic",
  heif: "image/heif",
};

export const UNSUPPORTED_IMAGE_MESSAGE =
  "Unsupported image type — use a JPEG, PNG, WebP, GIF or HEIC photo.";

export const IMAGE_TOO_LARGE_MESSAGE = "Each image must be under 5 MB.";

/** Matches the buckets' `file_size_limit` (5 MB). */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

/** A filename's lowercased extension, or "" when it has none. */
export function extensionOf(filename: string): string {
  const dot = filename.lastIndexOf(".");
  if (dot < 0 || dot === filename.length - 1) return "";
  return filename.slice(dot + 1).toLowerCase();
}

/** The MIME for an extension, or null when it isn't an image we accept. */
export function imageMimeForExtension(extension: string): string | null {
  return IMAGE_MIME_BY_EXTENSION[extension.toLowerCase()] ?? null;
}

/**
 * The MIME type to upload [file] as. Browsers report some formats oddly
 * (`image/jpg`) and nothing at all for others, so normalise — and return "" for
 * a file we can't identify, so it is refused rather than uploaded under a
 * guessed type.
 */
export function imageMimeOf(file: File): string {
  const type = (file.type || "").toLowerCase();
  if (type === "image/jpg") return "image/jpeg";
  if (type) return type;
  return imageMimeForExtension(extensionOf(file.name)) ?? "";
}

export function isAllowedImage(file: File): boolean {
  return (ALLOWED_IMAGE_MIME_TYPES as readonly string[]).includes(
    imageMimeOf(file),
  );
}
