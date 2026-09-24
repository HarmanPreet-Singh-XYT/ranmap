-- ---------------------------------------------------------------------------
-- Free-tier limits + shared usage metering.
--
-- Two ideas:
--   1. Hard count caps on the things a free account can accumulate (active
--      trips, group size, pinned photos), enforced by triggers so a modified
--      client can't bypass them. Pro lifts them.
--   2. A DB-backed meter for the metered AI / search allowances, so the count
--      is shared across server instances instead of living in a process's RAM.
--
-- Limit hits raise with a message beginning "Ranmap Pro required:" so the
-- client can tell them apart from real errors and show the paywall.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Usage meter (AI messages, map searches). Server-only.
-- ---------------------------------------------------------------------------
create table if not exists public.usage_counters (
  user_id uuid not null references public.profiles (id) on delete cascade,
  feature text not null,
  window_start timestamptz not null default now(),
  count int not null default 0,
  primary key (user_id, feature)
);

-- No policies: only the service role (which bypasses RLS) may read or write it.
alter table public.usage_counters enable row level security;

-- Consumes one unit of [p_user]'s allowance for [p_feature], rolling the window
-- when it has elapsed. Returns false once [p_max] uses have been made in the
-- current window. Row-locked so concurrent requests can't both squeak through.
create or replace function public.consume_usage(
  p_user uuid,
  p_feature text,
  p_max int,
  p_window_seconds int
)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
begin
  insert into public.usage_counters (user_id, feature, window_start, count)
  values (p_user, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select window_start, count into v_start, v_count
  from public.usage_counters
  where user_id = p_user and feature = p_feature
  for update;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  if v_count >= p_max then
    update public.usage_counters set window_start = v_start, count = v_count
    where user_id = p_user and feature = p_feature;
    return false;
  end if;

  update public.usage_counters set window_start = v_start, count = v_count + 1
  where user_id = p_user and feature = p_feature;
  return true;
end;
$$;

-- Lock it down: the meter is the server's, not the client's.
revoke all on function public.consume_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.consume_usage(uuid, text, int, int) to service_role;

-- ---------------------------------------------------------------------------
-- Free-tier limits (one place to tune them).
-- ---------------------------------------------------------------------------
create or replace function public.plan_limit(p_key text)
returns int language sql immutable as $$
  select case p_key
    when 'trips' then 3
    when 'group_members' then 6
    when 'map_posts' then 25
  end;
$$;

-- ---------------------------------------------------------------------------
-- Count caps. Each lapses for Pro.
-- ---------------------------------------------------------------------------

-- A free creator may keep at most N non-completed trips at once.
create or replace function public.enforce_trip_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_pro(new.created_by) then
    return new;
  end if;
  if (select count(*) from public.trips t
      where t.created_by = new.created_by
        and t.status in ('planned', 'active')) >= public.plan_limit('trips') then
    raise exception 'Ranmap Pro required: free accounts can plan up to % active trips at once.',
      public.plan_limit('trips') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trips_free_limit on public.trips;
create trigger trips_free_limit
  before insert on public.trips
  for each row execute function public.enforce_trip_limit();

-- A free user may pin at most N photos.
create or replace function public.enforce_map_post_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_pro(new.user_id) then
    return new;
  end if;
  if (select count(*) from public.map_posts p where p.user_id = new.user_id)
      >= public.plan_limit('map_posts') then
    raise exception 'Ranmap Pro required: free accounts can pin up to % photos.',
      public.plan_limit('map_posts') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists map_posts_free_limit on public.map_posts;
create trigger map_posts_free_limit
  before insert on public.map_posts
  for each row execute function public.enforce_map_post_limit();

-- A non-Pro group is capped; adding a Pro member (or to a Pro-enabled group)
-- is always allowed, and lifts the cap for everyone in it — "travel together".
create or replace function public.enforce_group_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_pro(new.user_id) or public.group_has_pro(new.group_id) then
    return new;
  end if;
  if (select count(*) from public.group_members m where m.group_id = new.group_id)
      >= public.plan_limit('group_members') then
    raise exception 'Ranmap Pro required: free groups are limited to % members.',
      public.plan_limit('group_members') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists group_members_free_limit on public.group_members;
create trigger group_members_free_limit
  before insert on public.group_members
  for each row execute function public.enforce_group_member_limit();
