-- ---------------------------------------------------------------------------
-- Ranmap migration 0021: add-usage metering (variable units).
--
-- The AI assistant now meters *tokens*, not messages, and token counts are only
-- known after the model responds — so a single increment-before-the-call (like
-- `consume_usage`) can't express it. This adds `add_usage`, which adds a
-- variable number of units to the counter (rolling the window exactly like
-- `consume_usage`/`usage_status`), so the route can record the real token spend
-- once the turn finishes.
--
-- The cap check itself is a separate read (`usage_status`) done before the
-- call: a token allowance can only ever be enforced "best effort" (a request
-- may overshoot by its own size), which is acceptable and expected.
--
-- Server-only: revoked from PUBLIC/anon/authenticated, granted to service_role.
-- ---------------------------------------------------------------------------
create or replace function public.add_usage(
  p_user uuid,
  p_feature text,
  p_units int,
  p_window_seconds int
)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
begin
  -- Nothing to record: report the current count without touching the row.
  if coalesce(p_units, 0) <= 0 then
    select uc.count into v_count
    from public.usage_counters uc
    where uc.user_id = p_user and uc.feature = p_feature;
    return coalesce(v_count, 0);
  end if;

  insert into public.usage_counters (user_id, feature, window_start, count)
  values (p_user, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  -- Roll the window before adding, so a stale count never absorbs the new units.
  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  v_count := v_count + p_units;

  update public.usage_counters set window_start = v_start, count = v_count
  where user_id = p_user and feature = p_feature;

  return v_count;
end;
$$;

revoke all on function public.add_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.add_usage(uuid, text, int, int) to service_role;
