-- ---------------------------------------------------------------------------
-- Ranmap migration 0055: the same storage-side limits for the other two buckets.
--
-- 0054 did this for `map-media`. These are the remaining user-writable buckets,
-- and each needs its own list because what they legitimately hold differs:
--
--   * `avatars` (public): profile photos. Both clients already check 5 MB and a
--     set of image types, so the bucket matches: the six types the mobile
--     allow-list defines. The web uploader's list is a deliberate subset
--     (browsers can't decode HEIC), and a client may be stricter than the
--     bucket — it just can't be looser.
--   * `documents` (private): the wallet holds scans *and PDFs* — the web
--     uploader accepts `application/pdf`, and `user_documents` has no column
--     restricting the format — so the list is the six image types plus PDF. Its
--     ceiling is larger than the photo buckets because a multi-page scan
--     legitimately is; the mobile client keeps its own stricter 5 MB check.
--
-- Limits apply to new uploads: objects already stored are unaffected.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

update storage.buckets
set
  file_size_limit = 5 * 1024 * 1024,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif'
  ]
where id = 'avatars';

update storage.buckets
set
  file_size_limit = 10 * 1024 * 1024,
  allowed_mime_types = array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
    'application/pdf'
  ]
where id = 'documents';
