-- ---------------------------------------------------------------------------
-- Auto-start for trips scheduled from the app.
--
-- `create_trip` recorded `trips.scheduled_start`, but the auto-starter
-- (`start_due_scheduled_trips`) only reads `public.scheduled_trips` — so a
-- start time chosen on the new-trip screen was displayed on the Trips list but
-- never actually fired. Bridge the two: when a future start is supplied, queue
-- it too, and the existing scheduler takes it from there.
--
-- Re-creates `create_trip` with the same signature and body, plus the queue
-- step. `create or replace` keeps the existing EXECUTE grants from
-- 0007_security_fixes.sql.
-- ---------------------------------------------------------------------------
create or replace function public.create_trip(
  p_title text,
  p_group_id uuid default null,
  p_scheduled_start timestamptz default null,
  p_origin_name text default null,
  p_origin_lat double precision default null,
  p_origin_lng double precision default null,
  p_destination_name text default null,
  p_destination_lat double precision default null,
  p_destination_lng double precision default null,
  p_route_polyline text default null
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip public.trips;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_title), '') = '' then
    raise exception 'title is required';
  end if;
  if p_group_id is not null and not public.is_group_member(p_group_id, v_uid) then
    raise exception 'not a member of the target group';
  end if;

  insert into public.trips (
    created_by, title, group_id, scheduled_start,
    origin_name, origin_point, destination_name, destination_point, route_polyline
  )
  values (
    v_uid, btrim(p_title), p_group_id, p_scheduled_start,
    p_origin_name,
    case when p_origin_lat is not null and p_origin_lng is not null
      then ST_SetSRID(ST_MakePoint(p_origin_lng, p_origin_lat), 4326)::geography end,
    p_destination_name,
    case when p_destination_lat is not null and p_destination_lng is not null
      then ST_SetSRID(ST_MakePoint(p_destination_lng, p_destination_lat), 4326)::geography end,
    p_route_polyline
  )
  returning * into v_trip;

  insert into public.trip_members (trip_id, user_id, invite_status, joined_at)
  values (v_trip.id, v_uid, 'accepted', now());

  -- Queue a *future* start so the scheduler fires it. A past time is left
  -- alone: it isn't a schedule, and silently starting the trip now would
  -- surprise the user.
  if p_scheduled_start is not null and p_scheduled_start > now() then
    insert into public.scheduled_trips (trip_id, scheduled_for, created_by_ai)
    select v_trip.id, p_scheduled_start, false
    where not exists (
      select 1 from public.scheduled_trips st where st.trip_id = v_trip.id
    );
  end if;

  return v_trip;
end;
$$;
