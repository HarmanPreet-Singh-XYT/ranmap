-- ---------------------------------------------------------------------------
-- Ranmap migration 0033: fair-use ceilings for Pro.
--
-- Migration 0010/0032 gave free accounts hard caps and let Pro bypass the
-- checks entirely — so "unlimited" was literally true, which is neither honest
-- nor safe (storage, provider quota). This migration keeps the free caps and
-- adds a generous Pro ceiling for each of the five capped resources.
--
-- Two distinct messages:
--   * free hit  -> 'Ranmap Pro required: ...'  (client shows the paywall)
--   * Pro hit   -> 'Plan limit reached: ...'   (client shows a plain error)
-- so a Pro user who hits their ceiling is never shown an "upgrade" paywall.
--
-- Existing rows above a ceiling are left alone — only new inserts are blocked.
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- plan_limit(): free and Pro keys. Re-created in full (matching 0012) so an
-- unknown key still raises rather than returning NULL (which a `count >= NULL`
-- comparison would read as "no cap").
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
  v_pro boolean := public.is_pro(new.created_by);
  v_limit int := public.plan_limit(case when v_pro then 'trips_pro' else 'trips' end);
begin
  if (select count(*) from public.trips t
      where t.created_by = new.created_by
        and t.status in ('planned', 'active')) >= v_limit then
    if v_pro then
      raise exception 'Plan limit reached: your plan includes up to % active trips at once.',
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
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(case when v_pro then 'map_posts_pro' else 'map_posts' end);
begin
  if (select count(*) from public.map_posts p where p.user_id = new.user_id)
      >= v_limit then
    if v_pro then
      raise exception 'Plan limit reached: your plan includes up to % pinned photos.',
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
-- Group-member ceiling. "Travel together": a Pro member lifts the group to the
-- Pro ceiling for everyone in it.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_group_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pro boolean := public.is_pro(new.user_id) or public.group_has_pro(new.group_id);
  v_limit int := public.plan_limit(case when v_pro then 'group_members_pro' else 'group_members' end);
begin
  if (select count(*) from public.group_members m where m.group_id = new.group_id)
      >= v_limit then
    if v_pro then
      raise exception 'Plan limit reached: this convoy is capped at % members.',
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
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(case when v_pro then 'documents_pro' else 'documents' end);
begin
  if (select count(*) from public.user_documents d where d.user_id = new.user_id)
      >= v_limit then
    if v_pro then
      raise exception 'Plan limit reached: your plan includes up to % documents.',
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
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(case when v_pro then 'route_templates_pro' else 'route_templates' end);
begin
  if (select count(*) from public.route_templates t where t.user_id = new.user_id)
      >= v_limit then
    if v_pro then
      raise exception 'Plan limit reached: your plan includes up to % saved routes.',
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
