-- ---------------------------------------------------------------------------
-- Plans + "travel together" group entitlements.
--
-- profiles.plan is written ONLY by the billing webhook (service role): the
-- client can read its own plan via my_plan() but has no UPDATE grant on these
-- columns, so it can never self-upgrade.
--
-- Benefits are per-user (the AI assistant) AND shared: if any accepted member
-- (or the creator/owner) of a trip/group is Pro, the whole trip/group is
-- Pro-enabled — so one subscriber unlocks voice for the entire crew. That is
-- the "travel together" angle, and it also makes the product spread on its own:
-- a free rider sees what Pro does and has a reason to subscribe for their own
-- trips later.
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists plan text not null default 'free',
  add column if not exists plan_expires_at timestamptz,
  add column if not exists plan_source text; -- ios | android | manual | ...

alter table public.profiles
  drop constraint if exists profiles_plan_check;
alter table public.profiles
  add constraint profiles_plan_check check (plan in ('free', 'pro'));

-- Keep the plan columns server-write-only. Supabase's default leaves a
-- table-level UPDATE grant on profiles, and a table-level privilege covers
-- every column regardless of column-level revokes — so (exactly as in
-- 0005_phone_verification.sql) drop it and re-grant only the client-writable
-- columns, deliberately omitting plan / plan_expires_at / plan_source.
revoke update on public.profiles from anon, authenticated;
grant update (username, display_name, avatar_id, vehicle_type, phone_number, socials)
  on public.profiles to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Entitlement predicates. SECURITY DEFINER, matching the 0002 helper pattern.
-- ---------------------------------------------------------------------------

-- A user's own active subscription. A null expiry means "no end date".
create or replace function public.is_pro(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user
      and p.plan = 'pro'
      and (p.plan_expires_at is null or p.plan_expires_at > now())
  );
$$;

-- A trip is Pro-enabled when its creator or any accepted member is Pro.
create or replace function public.trip_has_pro(p_trip uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.trips t
    where t.id = p_trip and public.is_pro(t.created_by)
  ) or exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip
      and m.invite_status = 'accepted'
      and public.is_pro(m.user_id)
  );
$$;

-- A group is Pro-enabled when its owner or any member is Pro.
create or replace function public.group_has_pro(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group and public.is_pro(g.owner_id)
  ) or exists (
    select 1 from public.group_members m
    where m.group_id = p_group and public.is_pro(m.user_id)
  );
$$;

-- Row-aware read of the caller's own plan. The column isn't in the public
-- select grant (same reasoning as phone_number/socials), so expose it here.
create or replace function public.my_plan()
returns table (plan text, plan_expires_at timestamptz, is_pro boolean)
language sql stable security definer set search_path = public as $$
  select p.plan, p.plan_expires_at, public.is_pro(p.id)
  from public.profiles p where p.id = auth.uid();
$$;

grant execute on function public.is_pro(uuid) to authenticated;
grant execute on function public.trip_has_pro(uuid) to authenticated;
grant execute on function public.group_has_pro(uuid) to authenticated;
grant execute on function public.my_plan() to authenticated;
