-- ---------------------------------------------------------------------------
-- Ranmap migration 0025: allowance RPCs return their new state.
--
-- With Redis as a *cache* in front of Postgres (rather than the only copy), the
-- client needs to refresh the cached counter after every write. Returning the
-- resulting state from `consume_usage` / `add_usage` lets it do that in the same
-- round-trip — no follow-up read, and no risk of the cache drifting.
--
-- Changing a function's return type can't be done with `create or replace`, so
-- both are dropped and recreated. Arguments are unchanged, so the existing
-- EXECUTE grants are re-issued for the same signatures.
-- ---------------------------------------------------------------------------

drop function if exists public.consume_usage(uuid, text, int, int);

create function public.consume_usage(
  p_user uuid,
  p_feature text,
  p_max int,
  p_window_seconds int
)
returns table (allowed boolean, used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
begin
  insert into public.usage_counters (user_id, feature, window_start, count)
  values (p_user, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  if v_count >= p_max then
    update public.usage_counters set window_start = v_start, count = v_count
    where user_id = p_user and feature = p_feature;
    return query select false, v_count, v_start;
    return;
  end if;

  v_count := v_count + 1;
  update public.usage_counters set window_start = v_start, count = v_count
  where user_id = p_user and feature = p_feature;
  return query select true, v_count, v_start;
end;
$$;

revoke all on function public.consume_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.consume_usage(uuid, text, int, int) to service_role;

drop function if exists public.add_usage(uuid, text, int, int);

create function public.add_usage(
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
begin
  -- Nothing to record: report the current state without touching the row.
  if coalesce(p_units, 0) <= 0 then
    select uc.count, uc.window_start into v_count, v_start
    from public.usage_counters uc
    where uc.user_id = p_user and uc.feature = p_feature;
    return query select coalesce(v_count, 0), coalesce(v_start, v_now);
    return;
  end if;

  insert into public.usage_counters (user_id, feature, window_start, count)
  values (p_user, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  -- Roll the window before adding, so a stale count never absorbs the units.
  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  v_count := v_count + p_units;

  update public.usage_counters set window_start = v_start, count = v_count
  where user_id = p_user and feature = p_feature;

  return query select v_count, v_start;
end;
$$;

revoke all on function public.add_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.add_usage(uuid, text, int, int) to service_role;
