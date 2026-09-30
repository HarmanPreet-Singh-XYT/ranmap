-- 0040_audit_fixes.sql
--
-- Closes the database findings from the security/UX audit. Additive and safe to
-- re-run: every function is `create or replace`, every policy is dropped before
-- being recreated, and every index/trigger is guarded.
--
-- What this fixes:
--   * my_trip_invites() no longer leaks a creator's private profile columns
--     (plan / phone_verified / plan_expires_at / plan_source) — it whitelists
--     the public fields instead of `to_jsonb(p) - …`.
--   * start_due_scheduled_trips() is granted to service_role; the scheduler's
--     RPC was denying because the revoke in 0038 removed the implicit PUBLIC
--     grant the service role relied on (see the grant repair in 0018).
--   * stop_proposals UPDATE can no longer move a proposal into a trip the
--     author isn't a member of.
--   * trip_legs UPDATE can no longer spoof created_by or reassign trip_id.
--   * notifications UPDATE is narrowed to read_at (was a table-wide grant).
--   * trip_shares gets explicit grants instead of relying on Supabase defaults.
--   * Missing FK/hot-path indexes on alert_checkins / group_alerts /
--     group_locations.
--   * notification_prefs / vehicle_service updated_at now auto-refresh.
--   * usage holds (reserve_usage) expire after 15 minutes, so a crashed request
--     that never settles can't strand a reservation for the whole window.

-- ---------------------------------------------------------------------------
-- 1. my_trip_invites: whitelist the creator's public profile fields.
-- ---------------------------------------------------------------------------
create or replace function public.my_trip_invites()
returns table (trip_id uuid, invite_status text, trips jsonb)
language sql stable security definer set search_path = public as $$
  select
    m.trip_id,
    m.invite_status,
    (to_jsonb(t) - 'origin_point' - 'destination_point' - 'route_polyline')
      || jsonb_build_object(
           'creator',
           (
             select jsonb_build_object(
               'id', p.id,
               'username', p.username,
               'display_name', p.display_name,
               'avatar_id', p.avatar_id,
               'vehicle_type', p.vehicle_type,
               'created_at', p.created_at,
               'updated_at', p.updated_at
             )
             from public.profiles p where p.id = t.created_by
           )
         )
  from public.trip_members m
  join public.trips t on t.id = m.trip_id
  where m.user_id = auth.uid()
    and m.invite_status = 'invited';
$$;

revoke execute on function public.my_trip_invites() from public, anon;
grant execute on function public.my_trip_invites() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. The scheduler's RPC must be callable by service_role. 0038 revoked the
--    implicit PUBLIC grant without re-granting, so the call was denied and
--    scheduled trips silently never started.
-- ---------------------------------------------------------------------------
grant execute on function public.start_due_scheduled_trips() to service_role;

-- ---------------------------------------------------------------------------
-- 3. stop_proposals: an UPDATE must stay within a trip the author belongs to.
--    (INSERT was already membership-checked in 0015; only UPDATE was open.)
-- ---------------------------------------------------------------------------
drop policy if exists "stop_proposals_update_creator" on public.stop_proposals;
create policy "stop_proposals_update_creator" on public.stop_proposals
  for update using (created_by = auth.uid())
  with check (
    created_by = auth.uid()
    and public.is_trip_participant(trip_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 4. trip_legs: freeze created_by and trip_id across UPDATE. The policy's
--    WITH CHECK only validates the *new* trip's membership, so without this a
--    participant could spoof authorship or move a leg between trips.
-- ---------------------------------------------------------------------------
create or replace function public.trip_legs_guard_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.created_by is distinct from old.created_by then
    raise exception 'trip_legs.created_by is immutable';
  end if;
  if new.trip_id is distinct from old.trip_id then
    raise exception 'trip_legs.trip_id is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists trip_legs_guard_update_trg on public.trip_legs;
create trigger trip_legs_guard_update_trg
  before update on public.trip_legs
  for each row execute function public.trip_legs_guard_update();

-- ---------------------------------------------------------------------------
-- 5. notifications: only read_at is client-writable.
-- ---------------------------------------------------------------------------
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 6. trip_shares: explicit grants (was left at the Supabase default ALL).
-- ---------------------------------------------------------------------------
revoke all on public.trip_shares from anon;
grant select, insert, delete on public.trip_shares to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Missing FK / hot-path indexes.
-- ---------------------------------------------------------------------------
create index if not exists alert_checkins_user_idx
  on public.alert_checkins (user_id);
create index if not exists group_alerts_created_by_idx
  on public.group_alerts (created_by);
create index if not exists group_alerts_resolved_by_idx
  on public.group_alerts (resolved_by)
  where resolved_by is not null;
create index if not exists group_locations_user_idx
  on public.group_locations (user_id);

-- ---------------------------------------------------------------------------
-- 8. Auto-refresh updated_at on the tables that were missing the trigger.
-- ---------------------------------------------------------------------------
drop trigger if exists notification_prefs_set_updated_at on public.notification_prefs;
create trigger notification_prefs_set_updated_at
  before update on public.notification_prefs
  for each row execute function public.set_updated_at();

drop trigger if exists vehicle_service_set_updated_at on public.vehicle_service;
create trigger vehicle_service_set_updated_at
  before update on public.vehicle_service
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 9. Usage holds expire. A crashed request (or a swallowed settle failure) used
--    to strand its reservation until the window rolled — for the AI meter that
--    is 30 days. Track when the current hold was taken and clear a hold older
--    than 15 minutes on the next reserve. A turn is bounded by a 30s upstream
--    timeout and 4 rounds, so 15 minutes is comfortably stale.
-- ---------------------------------------------------------------------------
alter table public.usage_counters
  add column if not exists reserved_at timestamptz;

comment on column public.usage_counters.reserved_at is
  'When the current in-flight hold was taken; a hold older than 15 minutes is treated as abandoned.';

create or replace function public.reserve_usage(
  p_user uuid,
  p_feature text,
  p_units int,
  p_max int,
  p_window_seconds int
)
returns table (allowed boolean, used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_reserved int;
  v_reserved_at timestamptz;
  v_units int := greatest(coalesce(p_units, 0), 0);
begin
  insert into public.usage_counters (user_id, feature, window_start, count, reserved)
  values (p_user, p_feature, v_now, 0, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count, uc.reserved, uc.reserved_at
    into v_start, v_count, v_reserved, v_reserved_at
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
    v_reserved := 0;
    v_reserved_at := null;
  elsif v_reserved > 0
        and (v_reserved_at is null or v_reserved_at < v_now - interval '15 minutes') then
    -- A hold that never settled — assume the request died and clear it.
    v_reserved := 0;
    v_reserved_at := null;
  end if;

  if v_count + v_reserved + v_units > p_max then
    update public.usage_counters
      set window_start = v_start, count = v_count,
          reserved = v_reserved, reserved_at = v_reserved_at
    where user_id = p_user and feature = p_feature;
    return query select false, v_count, v_start;
    return;
  end if;

  v_reserved := v_reserved + v_units;
  update public.usage_counters
    set window_start = v_start, count = v_count,
        reserved = v_reserved, reserved_at = v_now
  where user_id = p_user and feature = p_feature;
  return query select true, v_count, v_start;
end;
$$;

create or replace function public.release_usage(
  p_user uuid,
  p_feature text,
  p_units int,
  p_window_seconds int
)
returns table (used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_reserved int;
  v_units int := greatest(coalesce(p_units, 0), 0);
begin
  select uc.window_start, uc.count, uc.reserved into v_start, v_count, v_reserved
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if not found then
    return query select 0, v_now;
    return;
  end if;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
    v_reserved := 0;
  else
    v_reserved := greatest(v_reserved - v_units, 0);
  end if;

  update public.usage_counters
    set window_start = v_start, count = v_count, reserved = v_reserved,
        reserved_at = case when v_reserved = 0 then null else reserved_at end
  where user_id = p_user and feature = p_feature;
  return query select v_count, v_start;
end;
$$;

create or replace function public.settle_usage(
  p_user uuid,
  p_feature text,
  p_held int,
  p_actual int,
  p_window_seconds int
)
returns table (used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_reserved int;
  v_held int := greatest(coalesce(p_held, 0), 0);
  v_actual int := greatest(coalesce(p_actual, 0), 0);
begin
  select uc.window_start, uc.count, uc.reserved into v_start, v_count, v_reserved
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if not found then
    return query select 0, v_now;
    return;
  end if;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := v_actual;
    v_reserved := 0;
  else
    v_count := v_count + v_actual;
    v_reserved := greatest(v_reserved - v_held, 0);
  end if;

  update public.usage_counters
    set window_start = v_start, count = v_count, reserved = v_reserved,
        reserved_at = case when v_reserved = 0 then null else reserved_at end
  where user_id = p_user and feature = p_feature;
  return query select v_count, v_start;
end;
$$;
