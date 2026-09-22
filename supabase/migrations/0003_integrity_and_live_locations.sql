-- Ranmap migration 0003: integrity, atomicity, and live-location efficiency
--
-- Follow-ups to 0001/0002:
--   * a friendship pair could exist twice (A->B and B->A) — now unique
--   * creating a trip / group was two round-trips; if the membership insert
--     failed the group became invisible. Both are now single atomic RPCs.
--   * the map streamed *every* ping for a trip and reduced client-side
--     (O(n^2) bandwidth). `trip_member_locations` returns just the latest
--     ping per member.
--   * location_pings had no retention despite the "short retention" comment.
--
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- One row per friend pair, not one per direction.
-- ---------------------------------------------------------------------------
create unique index if not exists friendships_unique_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

-- ---------------------------------------------------------------------------
-- Atomic "create trip + add creator as an accepted member".
-- ---------------------------------------------------------------------------
create or replace function public.create_trip(
  p_title text,
  p_group_id uuid default null,
  p_scheduled_start timestamptz default null
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

  insert into public.trips (created_by, title, group_id, scheduled_start)
  values (v_uid, btrim(p_title), p_group_id, p_scheduled_start)
  returning * into v_trip;

  insert into public.trip_members (trip_id, user_id, invite_status, joined_at)
  values (v_trip.id, v_uid, 'accepted', now());

  return v_trip;
end;
$$;

grant execute on function public.create_trip(text, uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- Atomic "create group + add owner as a member".
-- ---------------------------------------------------------------------------
create or replace function public.create_group(p_name text)
returns public.groups
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;

  insert into public.groups (name, owner_id)
  values (btrim(p_name), v_uid)
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role)
  values (v_group.id, v_uid, 'owner');

  return v_group;
end;
$$;

grant execute on function public.create_group(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Latest ping per member for a trip. Readable only by accepted participants
-- (SECURITY DEFINER, but membership is checked explicitly). Returns the raw
-- `point` geography so PostgREST serialises it as GeoJSON, matching how the
-- client already parses location rows.
-- ---------------------------------------------------------------------------
create index if not exists location_pings_trip_user_time_idx
  on public.location_pings (trip_id, user_id, recorded_at desc);

create or replace function public.trip_member_locations(p_trip uuid)
returns table (
  user_id uuid,
  point geography,
  speed_mps real,
  heading real,
  recorded_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select distinct on (lp.user_id)
    lp.user_id, lp.point, lp.speed_mps, lp.heading, lp.recorded_at
  from public.location_pings lp
  where lp.trip_id = p_trip
    and public.is_trip_participant(p_trip, auth.uid())
  order by lp.user_id, lp.recorded_at desc;
$$;

grant execute on function public.trip_member_locations(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Retention: drop location pings older than `p_keep_days`. Pings are only
-- meaningful while a trip is live, so a finished trip's history doesn't need
-- to live forever. Callable by service_role / a scheduled job (not exposed to
-- authenticated users).
-- ---------------------------------------------------------------------------
create or replace function public.prune_location_pings(p_keep_days integer default 7)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_deleted integer;
begin
  delete from public.location_pings
  where recorded_at < now() - make_interval(days => greatest(p_keep_days, 1));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.prune_location_pings(integer) from public, anon, authenticated;

-- Schedule the prune daily if pg_cron happens to be available; ignore it
-- otherwise so the migration never fails.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('ranmap_prune_location_pings', '17 3 * * *', 'select public.prune_location_pings(7)');
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end;
$$;
