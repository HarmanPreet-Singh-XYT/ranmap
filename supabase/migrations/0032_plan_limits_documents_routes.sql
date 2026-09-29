-- ---------------------------------------------------------------------------
-- Ranmap migration 0032: free-tier limits for the documents wallet and the
-- saved-route library.
--
-- Both mirror the 0010 hard caps: a free account keeps ONE document and ONE
-- saved route; Pro lifts the cap. Enforced by BEFORE INSERT triggers so a
-- modified client can't bypass them, raising a message that begins
-- "Ranmap Pro required:" so the client maps it to the paywall
-- (looksPremiumRequired).
--
-- Existing rows above the cap are left alone — only new inserts are blocked.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Extend plan_limit() with the two new keys. Re-created in full (matching
-- 0012) so an unknown key still raises rather than returning NULL (which a
-- `count >= NULL` comparison would read as "no cap").
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
  end;
  if v_limit is null then
    raise exception 'unknown plan limit key: %', p_key;
  end if;
  return v_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- Document wallet cap. A free user may keep one document.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_document_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_pro(new.user_id) then
    return new;
  end if;
  if (select count(*) from public.user_documents d where d.user_id = new.user_id)
      >= public.plan_limit('documents') then
    raise exception 'Ranmap Pro required: free accounts can keep up to % document(s).',
      public.plan_limit('documents') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists user_documents_free_limit on public.user_documents;
create trigger user_documents_free_limit
  before insert on public.user_documents
  for each row execute function public.enforce_document_limit();

-- ---------------------------------------------------------------------------
-- Saved-route library cap. A free user may keep one saved route.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_route_template_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_pro(new.user_id) then
    return new;
  end if;
  if (select count(*) from public.route_templates t where t.user_id = new.user_id)
      >= public.plan_limit('route_templates') then
    raise exception 'Ranmap Pro required: free accounts can save up to % route(s).',
      public.plan_limit('route_templates') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists route_templates_free_limit on public.route_templates;
create trigger route_templates_free_limit
  before insert on public.route_templates
  for each row execute function public.enforce_route_template_limit();
