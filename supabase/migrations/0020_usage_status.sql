-- ---------------------------------------------------------------------------
-- Ranmap migration 0020: read-only usage meter.
--
-- `consume_usage` (0010) both reads and increments the counter, so the client
-- had no way to ask "how much is left?" without spending an allowance. This
-- adds a non-mutating read of the same counter, sharing the identical window
-- logic, so the app can render a quota meter before the limit is hit.
--
-- Server-only (the meter is the server's, not the client's): revoked from
-- PUBLIC/anon/authenticated, granted to service_role.
-- ---------------------------------------------------------------------------
create or replace function public.usage_status(
  p_user uuid,
  p_feature text,
  p_window_seconds int
)
returns table (used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_start timestamptz;
  v_count int;
  v_now timestamptz := now();
begin
  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature;

  -- No usage yet: nothing consumed, window starts now.
  if not found then
    return query select 0, v_now;
    return;
  end if;

  -- The window has elapsed; the next consume_usage will reset it, so report a
  -- fresh window with nothing used rather than the stale count.
  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    return query select 0, v_now;
    return;
  end if;

  return query select v_count, v_start;
end;
$$;

revoke all on function public.usage_status(uuid, text, int) from public, anon, authenticated;
grant execute on function public.usage_status(uuid, text, int) to service_role;
