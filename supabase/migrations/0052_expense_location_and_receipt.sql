-- ---------------------------------------------------------------------------
-- Ranmap migration 0052: an expense can remember where it happened and show the
-- bill.
--
-- Both are optional, and both are shared with the whole trip — an expense is
-- already visible to every participant, so its receipt should be too.
--
--   * `point` / `place_name` — the same shape `trip_stops` and `map_posts`
--     already use for a location, so the map helpers work on it unchanged.
--   * `receipt_path` — an object in the existing `map-media` bucket. Objects
--     live under the uploader's own folder, which the bucket's existing
--     insert/update/delete policies already cover, so only the *read* policy
--     needs widening: a receipt is visible to anyone on the trip it belongs to,
--     exactly like the trip's photos.
--
-- No UPDATE policy is added: an expense is written once, and nothing in the app
-- edits one after the fact.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------
alter table public.trip_expenses
add column if not exists point geography(point, 4326),
  add column if not exists place_name text,
  add column if not exists receipt_path text;
-- Keep free text in line with the other limits (0012).
alter table public.trip_expenses drop constraint if exists trip_expenses_place_name_len_chk;
alter table public.trip_expenses
add constraint trip_expenses_place_name_len_chk check (
    place_name is null
    or char_length(place_name) <= 200
  );
-- Widen the map-media read policy: it already covers the owner's own objects and
-- map photos visible to the caller; receipts join by the expense they belong to.
drop policy if exists "map_media_read_visible" on storage.objects;
create policy "map_media_read_visible" on storage.objects for
select using (
    bucket_id = 'map-media'
    and (
      (storage.foldername(name)) [1] = auth.uid()::text
      or exists (
        select 1
        from public.map_posts p
        where p.storage_path = storage.objects.name
          and public.can_view_map_post(p.id, auth.uid())
      )
      or exists (
        select 1
        from public.trip_expenses e
        where e.receipt_path = storage.objects.name
          and public.is_trip_participant(e.trip_id, auth.uid())
      )
    )
  );