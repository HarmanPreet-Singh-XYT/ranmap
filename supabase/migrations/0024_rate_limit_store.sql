-- ---------------------------------------------------------------------------
-- Ranmap migration 0024: shared rate-limit store.
--
-- The limiter's buckets used to live in a per-process Map, so running more than
-- one server instance multiplied every limit by the instance count. This moves
-- the counters into Postgres (like `usage_counters`), so all instances share
-- one view of a bucket.
--
-- Fixed window per key (the previous in-memory store was a sliding window; a
-- fixed window is the standard trade for a shared store and is what the
-- `Retry-After` is computed from).
--
-- Server-only: revoked from PUBLIC/anon/authenticated, granted to service_role.
-- ---------------------------------------------------------------------------
create table if not exists public.rate_limit_counters (
  key text primary key,
  window_start timestamptz not null default now(),
  count int not null default 0
);

-- No policies: only the service role (which bypasses RLS) may read or write it.
alter table public.rate_limit_counters enable row level security;

-- Records one hit against [p_key] and reports whether it is allowed. Row-locked
-- so concurrent requests across instances can't both squeak past the limit.
create or replace function public.consume_rate_limit(
  p_key text,
  p_window_seconds int,
  p_max int
)
returns table (allowed boolean, retry_after_seconds int)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_window int := greatest(p_window_seconds, 1);
  v_max int := greatest(p_max, 1);
begin
  if coalesce(btrim(p_key), '') = '' then
    raise exception 'key is required';
  end if;

  insert into public.rate_limit_counters (key, window_start, count)
  values (p_key, v_now, 0)
  on conflict (key) do nothing;

  select c.window_start, c.count into v_start, v_count
  from public.rate_limit_counters c
  where c.key = p_key
  for update;

  if v_start + make_interval(secs => v_window) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  if v_count >= v_max then
    update public.rate_limit_counters set window_start = v_start, count = v_count
    where key = p_key;
    return query
      select false,
        greatest(
          1,
          ceil(extract(epoch from (v_start + make_interval(secs => v_window) - v_now)))
        )::int;
    return;
  end if;

  v_count := v_count + 1;
  update public.rate_limit_counters set window_start = v_start, count = v_count
  where key = p_key;
  return query select true, 0;
end;
$$;

revoke all on function public.consume_rate_limit(text, int, int) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(text, int, int) to service_role;
