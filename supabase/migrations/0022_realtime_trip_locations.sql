-- ---------------------------------------------------------------------------
-- Ranmap migration 0022: authorize the live-position broadcast channel.
--
-- Live positions now travel over an ephemeral Realtime *broadcast* channel
-- (topic `trip-locations:<trip_id>`) instead of writing one `location_pings`
-- row per 5 m of movement. Broadcasts are not backed by a table, so the only
-- thing gating them is Realtime Authorization: a channel marked private is
-- checked against Row Level Security policies on `realtime.messages`.
--
-- These two policies mean only an *accepted member* of the topic's trip may
-- publish (INSERT) or receive (SELECT) on it. The trip id is the second
-- `:`-separated segment of the topic.
--
-- The persisted `location_pings` trail (now coarse) keeps its own table RLS,
-- so the authoritative route data is unaffected.
-- ---------------------------------------------------------------------------

drop policy if exists "trip_locations_receive" on realtime.messages;
create policy "trip_locations_receive" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
      from public.trip_members m
      where m.user_id = auth.uid()
        and m.invite_status = 'accepted'
        and m.trip_id::text = split_part(realtime.topic(), ':', 2)
    )
  );

drop policy if exists "trip_locations_send" on realtime.messages;
create policy "trip_locations_send" on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
      from public.trip_members m
      where m.user_id = auth.uid()
        and m.invite_status = 'accepted'
        and m.trip_id::text = split_part(realtime.topic(), ':', 2)
    )
  );
