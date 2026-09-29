-- ---------------------------------------------------------------------------
-- Ranmap migration 0034: the Extreme tier.
--
-- Adds a third, top plan. Tiers are ordered: free < pro < extreme. Existing
-- "Pro" entitlements stay meaningful by making `is_pro` mean *paid*
-- (pro OR extreme), so every current Pro gate keeps working and Extreme is a
-- strict superset. `is_extreme` identifies the top tier for the (higher)
-- ceilings.
--
-- Caps: each resource gains a `*_extreme` key in `plan_limit`, and the five
-- enforce triggers resolve the caller's tier into free/pro/extreme. A free hit
-- still raises 'Ranmap Pro required:' (paywall); a Pro/Extreme hit raises
-- 'Plan limit reached:' (a plain error, no paywall).
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Widen the plan domain.
-- ---------------------------------------------------------------------------
alter table public.profiles
  drop constraint if exists profiles_plan_check;
alter table public.profiles
  add constraint profiles_plan_check check (plan in ('free', 'pro', 'extreme'));

-- ---------------------------------------------------------------------------
-- Entitlement predicates. `is_pro` is deliberately widened to mean "paid": all
-- existing gates (voice, caps, trip/group unlocks) then treat Extreme as Pro.
-- ---------------------------------------------------------------------------
create or replace function public.is_pro(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user
      and p.plan in ('pro', 'extreme')
      and (p.plan_expires_at is null or p.plan_expires_at > now())
  );
$$;

create or replace function public.is_extreme(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user
      and p.plan = 'extreme'
      and (p.plan_expires_at is null or p.plan_expires_at > now())
  );
$$;

-- A group is Extreme-enabled when its owner or any member is Extreme.
create or replace function public.group_has_extreme(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group and public.is_extreme(g.owner_id)
  ) or exists (
    select 1 from public.group_members m
    where m.group_id = p_group and public.is_extreme(m.user_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- Row-aware read of the caller's own plan, now carrying the tier flags. The
-- return type changes, so the function is dropped and re-created (CREATE OR
-- REPLACE can't alter the RETURNS TABLE shape) — the client reads by column
-- name, so the added column is backward-compatible.
-- ---------------------------------------------------------------------------
drop function if exists public.my_plan();
create or replace function public.my_plan()
returns table (
  plan text,
  plan_expires_at timestamptz,
  is_pro boolean,
  is_extreme boolean
)
language sql stable security definer set search_path = public as $$
  select p.plan, p.plan_expires_at, public.is_pro(p.id), public.is_extreme(p.id)
  from public.profiles p where p.id = auth.uid();
$$;

grant execute on function public.is_extreme(uuid) to authenticated;
grant execute on function public.group_has_extreme(uuid) to authenticated;
grant execute on function public.my_plan() to authenticated;

-- ---------------------------------------------------------------------------
-- Fair-use ceilings. Free and Pro keys already exist (0010/0032/0033); this
-- adds the Extreme tier. Re-created in full (matching 0012) so an unknown key
-- still raises rather than returning NULL (a `count >= NULL` reads as no cap).
-- ---------------------------------------------------------------------------
create or replace function public.plan_limit(p_key text)
returns int language plpgsql immutable as $$
declare
  v_limit int;
begin
  v_limit := case p_key
    when 'trips' then 3
    when 'group_members' then 6
    when 'map_posts' then 25
    when 'documents' then 1
    when 'route_templates' then 1
    when 'trips_pro' then 100
    when 'group_members_pro' then 100
    when 'map_posts_pro' then 5000
    when 'documents_pro' then 100
    when 'route_templates_pro' then 100
    when 'trips_extreme' then 250
    when 'group_members_extreme' then 250
    when 'map_posts_extreme' then 20000
    when 'documents_extreme' then 500
    when 'route_templates_extreme' then 500
  end;
  if v_limit is null then
    raise exception 'unknown plan limit key: %', p_key;
  end if;
  return v_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- Active-trip ceiling.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_trip_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.created_by);
  v_pro boolean := public.is_pro(new.created_by);
  v_limit int := public.plan_limit(
    case when v_extreme then 'trips_extreme'
         when v_pro then 'trips_pro'
         else 'trips' end);
begin
  if (select count(*) from public.trips t
      where t.created_by = new.created_by
        and t.status in ('planned', 'active')) >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % active trips.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % active trips. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can plan up to % active trips at once.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trips_free_limit on public.trips;
create trigger trips_free_limit
  before insert on public.trips
  for each row execute function public.enforce_trip_limit();

-- ---------------------------------------------------------------------------
-- Photo-pin ceiling.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_map_post_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'map_posts_extreme'
         when v_pro then 'map_posts_pro'
         else 'map_posts' end);
begin
  if (select count(*) from public.map_posts p where p.user_id = new.user_id)
      >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % pinned photos.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % pinned photos. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can pin up to % photos.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists map_posts_free_limit on public.map_posts;
create trigger map_posts_free_limit
  before insert on public.map_posts
  for each row execute function public.enforce_map_post_limit();

-- ---------------------------------------------------------------------------
-- Group-member ceiling. "Travel together": an Extreme member lifts the group to
-- the Extreme ceiling for everyone in it.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_group_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id) or public.group_has_extreme(new.group_id);
  v_pro boolean := public.is_pro(new.user_id) or public.group_has_pro(new.group_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'group_members_extreme'
         when v_pro then 'group_members_pro'
         else 'group_members' end);
begin
  if (select count(*) from public.group_members m where m.group_id = new.group_id)
      >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: this convoy is capped at % members.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: this convoy is capped at % members. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free groups are limited to % members.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists group_members_free_limit on public.group_members;
create trigger group_members_free_limit
  before insert on public.group_members
  for each row execute function public.enforce_group_member_limit();

-- ---------------------------------------------------------------------------
-- Document-wallet ceiling.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_document_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'documents_extreme'
         when v_pro then 'documents_pro'
         else 'documents' end);
begin
  if (select count(*) from public.user_documents d where d.user_id = new.user_id)
      >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % documents.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % documents. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can keep up to % document(s).',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists user_documents_free_limit on public.user_documents;
create trigger user_documents_free_limit
  before insert on public.user_documents
  for each row execute function public.enforce_document_limit();

-- ---------------------------------------------------------------------------
-- Saved-route ceiling.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_route_template_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'route_templates_extreme'
         when v_pro then 'route_templates_pro'
         else 'route_templates' end);
begin
  if (select count(*) from public.route_templates t where t.user_id = new.user_id)
      >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % saved routes.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % saved routes. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can save up to % route(s).',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists route_templates_free_limit on public.route_templates;
create trigger route_templates_free_limit
  before insert on public.route_templates
  for each row execute function public.enforce_route_template_limit();
