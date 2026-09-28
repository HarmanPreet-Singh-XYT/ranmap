-- ---------------------------------------------------------------------------
-- Ranmap migration 0023: server-attested live-position broadcast.
--
-- A Realtime broadcast payload carries no server-attested sender (the wire
-- frame is only join_ref/ref/topic/event/payload, and the client sets its own
-- ref), so a member publishing directly could forge another member's position.
--
-- So clients no longer publish. They call `broadcast_position`, which:
--   * verifies the caller via auth.uid() and the trip's membership (accepted
--     only), and
--   * emits the broadcast itself with the sender id stamped by the database.
--
-- Still no `location_pings` row — this is an ephemeral broadcast, just
-- DB-authored. The client INSERT policy added in 0022 is dropped so a client
-- can no longer publish on the channel directly.
--
-- NOTE: uses `realtime.send(payload, event, topic, private)`. If a given
-- Supabase project doesn't expose that helper, `realtime.broadcast_changes` is
-- the alternative — verify on the target project (the migration fails loudly
-- rather than silently disabling live positions).
-- ---------------------------------------------------------------------------

drop policy if exists "trip_locations_send" on realtime.messages;

create or replace function public.broadcast_position(
  p_trip uuid,
  p_lat double precision,
  p_lng double precision,
  p_speed double precision default null,
  p_heading double precision default null
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1
    from public.trip_members m
    where m.trip_id = p_trip
      and m.user_id = v_uid
      and m.invite_status = 'accepted'
  ) then
    raise exception 'not a member of this trip';
  end if;
  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90
     or p_lng < -180 or p_lng > 180 then
    raise exception 'invalid coordinates';
  end if;

  -- The sender id is stamped here, from auth.uid() — the client cannot choose
  -- it. Speed/heading are normalised so a nonsensical reading is dropped
  -- rather than broadcast (geolocator reports a negative speed when it has no
  -- reading).
  perform realtime.send(
    jsonb_build_object(
      'user_id', v_uid,
      'lat', p_lat,
      'lng', p_lng,
      'speed_mps', case when p_speed >= 0 then p_speed else null end,
      'heading', case when p_heading >= 0 and p_heading <= 360 then p_heading else null end,
      'recorded_at', now()
    ),
    'position',
    'trip-locations:' || p_trip::text,
    true  -- private: receivers still need the RLS SELECT policy from 0022
  );
end;
$$;

revoke all on function public.broadcast_position(
  uuid, double precision, double precision, double precision, double precision
) from public, anon;
grant execute on function public.broadcast_position(
  uuid, double precision, double precision, double precision, double precision
) to authenticated;
