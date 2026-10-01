-- ---------------------------------------------------------------------------
-- Ranmap migration 0054: enforce the image limits in storage, not just the app.
--
-- Both clients check a file's size and type before uploading (`imageUploadError`
-- / the web form's own check), but that is courtesy code: `map-media` accepted
-- anything up to the platform default, so a modified client could push a 100 MB
-- file or a non-image into the shared bucket.
--
-- Supabase's `storage.buckets` carries the real limits, and storage enforces
-- them on upload. They mirror the client rules exactly — 5 MB, the same six
-- image types (`lib/core/util/image_upload.dart`) — so nothing a legitimate
-- client sends is affected.
--
-- The bucket holds map photos *and* expense attachments, so both get the same
-- ceiling, which is what the app already assumed.
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
where id = 'map-media';
