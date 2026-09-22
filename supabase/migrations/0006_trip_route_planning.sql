-- Ranmap migration 0006: trip route planning
--
-- trips.origin_point/destination_point/route_polyline existed in the schema
-- from 0001 but nothing ever wrote them — create_trip only accepted a
-- title/group/schedule. Extends it to optionally take origin/destination/
-- route in the same atomic call, and adds an update_trip_route RPC for
-- setting/changing the route on an already-created trip (e.g. picking a
-- different alternate route, or planning a route after the fact).
--
-- Safe to re-run.

-- `create or replace` cannot change a function's argument list, so the 3-arg
-- create_trip added in 0003 is a distinct overload — drop it explicitly.
-- Otherwise PostgREST sees two overloads and can't decide which to call.
drop function if exists public.create_trip(text, uuid, timestamptz);

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

  return v_trip;
end;
$$;

grant execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Set/replace the planned route on an existing trip. Participant-gated
-- rather than creator-only, since anyone on the trip may want to switch to
-- an alternate route.
-- ---------------------------------------------------------------------------
create or replace function public.update_trip_route(
  p_trip uuid,
  p_origin_name text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_destination_name text,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_route_polyline text
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_trip public.trips;
begin
  if not public.is_trip_participant(p_trip, auth.uid()) then
    raise exception 'not a participant of this trip';
  end if;

  update public.trips set
    origin_name = p_origin_name,
    origin_point = ST_SetSRID(ST_MakePoint(p_origin_lng, p_origin_lat), 4326)::geography,
    destination_name = p_destination_name,
    destination_point = ST_SetSRID(ST_MakePoint(p_destination_lng, p_destination_lat), 4326)::geography,
    route_polyline = p_route_polyline
  where id = p_trip
  returning * into v_trip;

  return v_trip;
end;
$$;

grant execute on function public.update_trip_route(
  uuid, text, double precision, double precision, text, double precision, double precision, text
) to authenticated;
