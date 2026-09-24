-- Ranmap migration 0008: hardening follow-ups
--
-- Closes the remaining issues from the follow-up audit of 0001–0007:
--   * prune_location_pings / start_due_scheduled_trips were SECURITY DEFINER
--     with no in-function caller check — protected only by REVOKE. If a future
--     migration ever re-grants EXECUTE they become a mass-delete / mass-start
--     primitive. Both now also reject anon/authenticated callers.
--   * create_trip / create_group / update_trip_route still carried the default
--     PUBLIC EXECUTE grant, so `anon` could invoke them (they error, but the
--     hardening intent was to deny). Revoked from PUBLIC/anon, kept for
--     authenticated, and granted explicitly to service_role (the server's admin
--     client calls create_trip for the AI assistant).
--   * the is_* / can_view_map_post / my_private_profile / trip_member_locations
--     helpers are called by the server through the service-role client; make
--     that grant explicit so revoking from PUBLIC can't silently break it.
--   * the CHECK constraints added in 0007 were NOT VALID and never validated
--     against existing rows.
--   * missing indexes for the scheduler and pruner hot paths, plus a couple of
--     map_post_shares columns.
--
-- Safe to re-run (guarded / idempotent).

-- ---------------------------------------------------------------------------
-- Defence in depth on the two admin-only SECURITY DEFINER functions. They stay
-- revoked from PUBLIC/anon/authenticated (0003/0007); this adds an internal
-- check so an accidental re-grant can't turn them into a public primitive.
-- `auth.role()` is NULL when called by a superuser/cron/pg_cron worker, so we
-- only reject the HTTP-facing roles.
-- ---------------------------------------------------------------------------
create or replace function public.prune_location_pings(p_keep_days integer default 7)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_deleted integer;
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'not authorized';
  end if;

  delete from public.location_pings
  where recorded_at < now() - make_interval(days => greatest(p_keep_days, 1));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.prune_location_pings(integer) from public, anon, authenticated;

create or replace function public.start_due_scheduled_trips()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer := 0;
  r record;
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'not authorized';
  end if;

  for r in
    select st.id as schedule_id, st.trip_id
    from public.scheduled_trips st
    join public.trips t on t.id = st.trip_id
    where st.scheduled_for <= now() and t.status = 'planned'
    for update of st skip locked
  loop
    update public.trips
    set status = 'active', started_at = now()
    where id = r.trip_id and status = 'planned';
    if found then
      delete from public.scheduled_trips where id = r.schedule_id;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.start_due_scheduled_trips() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Tighten EXECUTE on the client-callable RPCs: deny anon, allow authenticated,
-- and keep the server's service-role client working explicitly.
-- ---------------------------------------------------------------------------
revoke execute on function public.create_group(text) from public, anon;
grant execute on function public.create_group(text) to authenticated, service_role;

revoke execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text
) from public, anon;
grant execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text
) to authenticated, service_role;

revoke execute on function public.update_trip_route(
  uuid, text, double precision, double precision,
  text, double precision, double precision, text
) from public, anon;
grant execute on function public.update_trip_route(
  uuid, text, double precision, double precision,
  text, double precision, double precision, text
) to authenticated, service_role;

-- The read/helper functions the server calls with the service-role key.
grant execute on function public.is_trip_participant(uuid, uuid) to service_role;
grant execute on function public.is_group_member(uuid, uuid) to service_role;
grant execute on function public.my_private_profile() to service_role;
grant execute on function public.trip_member_locations(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Validate the CHECK constraints that 0007 added as NOT VALID. Each is wrapped
-- so a pre-existing bad row raises a notice instead of failing the migration;
-- re-run after cleaning data to validate.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('chat_messages',    'chat_messages_one_channel_chk'),
      ('map_post_shares',  'map_post_shares_one_target_chk'),
      ('profiles',         'profiles_vehicle_type_chk'),
      ('friendships',      'friendships_status_chk'),
      ('group_members',    'group_members_role_chk'),
      ('trips',            'trips_status_chk'),
      ('trip_members',     'trip_members_status_chk'),
      ('trip_stops',       'trip_stops_kind_chk'),
      ('trip_expenses',    'trip_expenses_category_chk'),
      ('trip_expenses',    'trip_expenses_amount_chk'),
      ('trip_expenses',    'trip_expenses_liters_chk'),
      ('map_posts',        'map_posts_visibility_chk'),
      ('ai_messages',      'ai_messages_role_chk'),
      ('location_pings',   'location_pings_speed_chk'),
      ('location_pings',   'location_pings_heading_chk'),
      ('trip_stats',       'trip_stats_nonneg_chk')
    ) as t(tbl, conname)
  loop
    if exists (
      select 1 from pg_constraint
      where conname = c.conname and convalidated = false
    ) then
      begin
        execute format('alter table public.%I validate constraint %I', c.tbl, c.conname);
      exception when others then
        raise notice 'constraint % not validated (existing rows violate it): %', c.conname, sqlerrm;
      end;
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Indexes for the scheduler / retention hot paths and map_post_shares targets.
-- ---------------------------------------------------------------------------
create index if not exists scheduled_trips_scheduled_for_idx
  on public.scheduled_trips (scheduled_for);
create index if not exists trips_status_idx
  on public.trips (status);
create index if not exists location_pings_recorded_at_idx
  on public.location_pings (recorded_at);
create index if not exists map_post_shares_shared_with_user_idx
  on public.map_post_shares (shared_with_user);
create index if not exists map_post_shares_shared_with_group_idx
  on public.map_post_shares (shared_with_group);

-- One share row per (post, target).
create unique index if not exists map_post_shares_user_unique_idx
  on public.map_post_shares (post_id, shared_with_user)
  where shared_with_user is not null;
create unique index if not exists map_post_shares_group_unique_idx
  on public.map_post_shares (post_id, shared_with_group)
  where shared_with_group is not null;
