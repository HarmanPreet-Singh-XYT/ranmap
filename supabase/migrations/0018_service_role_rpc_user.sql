-- ---------------------------------------------------------------------------
-- Ranmap migration 0018: let the AI copilot's service-role client act on
-- behalf of a user, and close scheduled_trips duplication.
--
-- Bug: the AI server calls `create_trip` and `propose_stop` through the
-- service-role client (server/src/lib/ai-tools.ts). Both derived the actor
-- from `auth.uid()`, which is NULL under a service-role key — so every
-- "create a trip" / "propose a stop" request raised 'not authenticated' and
-- the copilot returned a generic failure. Neither call could ever succeed.
--
-- Fix: add an explicit `p_user uuid default null` to both functions.
-- `coalesce(p_user, auth.uid())` preserves the app's behaviour (which never
-- passes p_user) while the server can name the user it is acting for. Passing
-- p_user explicitly is restricted to service_role, so an authenticated client
-- cannot forge another user's identity.
--
-- Also: dedupe `scheduled_trips` and add a unique index on trip_id so the AI's
-- `schedule_trip` tool can't queue two rows for one trip.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- create_trip: recreate with p_user. The old overload is dropped first —
-- adding a parameter creates a *new* signature, and leaving both would make
-- PostgREST's named-argument resolution ambiguous.
-- ---------------------------------------------------------------------------
drop function if exists public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text
);

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
  p_route_polyline text default null,
  p_user uuid default null
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid;
  v_trip public.trips;
begin
  -- Only the service-role (the AI server) may act as an explicit user;
  -- a normal authenticated client must derive its identity from the JWT.
  if p_user is not null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'not authorized to specify a user';
  end if;

  v_uid := coalesce(p_user, auth.uid());
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

revoke execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text, uuid
) from public, anon;
grant execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- propose_stop: recreate with p_user, same service-role-only override.
-- ---------------------------------------------------------------------------
drop function if exists public.propose_stop(
  uuid, text, text, double precision, double precision
);

create or replace function public.propose_stop(
  p_trip uuid,
  p_name text,
  p_note text default null,
  p_lat double precision default null,
  p_lng double precision default null,
  p_user uuid default null
)
returns public.stop_proposals
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid;
  v_prop public.stop_proposals;
begin
  if p_user is not null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'not authorized to specify a user';
  end if;

  v_uid := coalesce(p_user, auth.uid());
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip and m.user_id = v_uid
  ) then
    raise exception 'not a member of this trip';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;

  insert into public.stop_proposals (trip_id, created_by, name, note, lat, lng)
  values (p_trip, v_uid, btrim(p_name), p_note, p_lat, p_lng)
  returning * into v_prop;

  return v_prop;
end;
$$;

revoke execute on function public.propose_stop(
  uuid, text, text, double precision, double precision, uuid
) from public, anon;
grant execute on function public.propose_stop(
  uuid, text, text, double precision, double precision, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- scheduled_trips: one schedule per trip. Dedupe existing rows (keep the
-- earliest scheduled_for, tie-broken by id) before adding the unique index, so
-- a project that already has duplicates from the AI tool still migrates.
-- ---------------------------------------------------------------------------
delete from public.scheduled_trips st
using public.scheduled_trips st2
where st.trip_id = st2.trip_id
  and (
    st.scheduled_for > st2.scheduled_for
    or (st.scheduled_for = st2.scheduled_for and st.id > st2.id)
  );

create unique index if not exists scheduled_trips_trip_unique_idx
  on public.scheduled_trips (trip_id);

-- ---------------------------------------------------------------------------
-- The Node scheduler can now run the retention prune, since pg_cron may not be
-- installed. Grant it explicitly (0008 revoked it from PUBLIC/anon/
-- authenticated, which also drops service_role's default PUBLIC grant).
-- ---------------------------------------------------------------------------
grant execute on function public.prune_location_pings(integer) to service_role;
