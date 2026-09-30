-- 0044_drop_chat_attachment_path.sql
--
-- Drops the vestigial chat_messages.attachment_path column. It was introduced in
-- 0001 for a file-per-message design that was never built: chat images now ride
-- on map_posts via kind = 'photo' + payload.posts (see 0043), and no client or
-- server code reads or writes attachment_path. The column is dead weight and a
-- trap for future work, so remove it rather than leave it drifting.
--
-- Safe to re-run: the column is dropped only if present, and its length check
-- (chat_messages_attachment_len_chk, added in 0035) is dropped first — dropping
-- the column would take the constraint with it anyway, but naming it explicitly
-- keeps the intent clear.

alter table public.chat_messages
  drop constraint if exists chat_messages_attachment_len_chk;

alter table public.chat_messages
  drop column if exists attachment_path;
