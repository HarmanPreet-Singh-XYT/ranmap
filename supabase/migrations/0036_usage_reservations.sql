-- ---------------------------------------------------------------------------
-- Ranmap migration 0036: in-flight reservations no longer count as usage.
--
-- The AI token allowance is metered with an up-front reservation (0035): the
-- route holds an upper-bound cost before the model runs, then refunds the
-- unspent part. That hold was stored in `usage_counters.count` — the same column
-- the quota meter (`usage_status`) reads — so a turn that really cost ~1k tokens
-- showed as an ~8k jump in the meter until the refund landed, and a refund that
-- failed (best effort, only logged) left the overcharge in place for good.
--
-- Splitting the two concerns fixes that: `count` is settled spend (what the
-- meter and the pre-call check read), `reserved` is the in-flight hold (what
-- bounds concurrent turns). `reserve_usage` now moves units into `reserved`, and
-- the new `settle_usage` records the real spend into `count` and releases the
-- hold in one atomic step, so the two counters can't drift apart.
-- ---------------------------------------------------------------------------

alter table public.usage_counters
  add column if not exists reserved int not null default 0;

comment on column public.usage_counters.reserved is
  'In-flight reservation held by a running request; never reported as usage.';

-- Holds [p_units] for a running request, refusing when count + reserved + units
-- would exceed [p_max]. Returns the *settled* count as `used`, so a caller that
-- refreshes its cache from the result keeps the meter honest (the hold is
-- deliberately absent from the returned state).
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
  v_units int := greatest(coalesce(p_units, 0), 0);
begin
  insert into public.usage_counters (user_id, feature, window_start, count, reserved)
  values (p_user, p_feature, v_now, 0, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count, uc.reserved into v_start, v_count, v_reserved
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
    v_reserved := 0;
  end if;

  if v_count + v_reserved + v_units > p_max then
    update public.usage_counters
      set window_start = v_start, count = v_count, reserved = v_reserved
    where user_id = p_user and feature = p_feature;
    return query select false, v_count, v_start;
    return;
  end if;

  v_reserved := v_reserved + v_units;
  update public.usage_counters
    set window_start = v_start, count = v_count, reserved = v_reserved
  where user_id = p_user and feature = p_feature;
  return query select true, v_count, v_start;
end;
$$;

revoke all on function public.reserve_usage(uuid, text, int, int, int) from public, anon, authenticated;
grant execute on function public.reserve_usage(uuid, text, int, int, int) to service_role;

-- Releases a hold without recording any spend — a turn that produced nothing.
-- Never goes below zero, and a rolled window means there is nothing to release.
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
    set window_start = v_start, count = v_count, reserved = v_reserved
  where user_id = p_user and feature = p_feature;
  return query select v_count, v_start;
end;
$$;

revoke all on function public.release_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.release_usage(uuid, text, int, int) to service_role;

-- Settles a hold against the real spend in one atomic step: [p_actual] units
-- land in `count` (visible) and [p_held] comes out of `reserved`. Both happen
-- here rather than as a separate add + release, so a failure between them can't
-- strand a hold or leave a turn uncharged.
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
    -- The window rolled while the turn ran: the hold belonged to the old
    -- window, so drop it and charge the real spend against the fresh one.
    v_start := v_now;
    v_count := v_actual;
    v_reserved := 0;
  else
    v_count := v_count + v_actual;
    v_reserved := greatest(v_reserved - v_held, 0);
  end if;

  update public.usage_counters
    set window_start = v_start, count = v_count, reserved = v_reserved
  where user_id = p_user and feature = p_feature;
  return query select v_count, v_start;
end;
$$;

revoke all on function public.settle_usage(uuid, text, int, int, int) from public, anon, authenticated;
grant execute on function public.settle_usage(uuid, text, int, int, int) to service_role;

-- `add_usage` (0021) existed only for the old "charge after the call" model,
-- which reserve + settle now replaces. Dropping it removes a second metering
-- path that bypasses the reservation.
drop function if exists public.add_usage(uuid, text, int, int);
