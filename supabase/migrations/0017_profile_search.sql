-- ---------------------------------------------------------------------------
-- Ranmap migration 0017: forgiving (fuzzy) username search.
--
-- The client's "Find people" search previously ran an exact substring match
-- (`ilike '%query%'`), so a single typo ("daev" for "dave") returned nothing
-- and the user was left with no way to tell a typo from a nonexistent account.
--
-- This adds `search_profiles(p_query)`, which matches on a substring *or* a
-- trigram similarity (pg_trgm), ranked so the closest handles come first. The
-- client calls it and falls back to the old substring search if the function
-- is missing, so the app keeps working before/without this migration.
--
-- Additive only: one extension, one index, one function. Existing tables,
-- policies and functions are untouched.
--
-- Safe to re-run (`create extension`/`create index` are `if not exists` and
-- the function is `create or replace`).
-- ---------------------------------------------------------------------------

-- pg_trgm powers the `%` similarity operator and the GIN index below.
create extension if not exists pg_trgm;

-- Makes the similarity / `%` lookups index-assisted on a large profiles table.
create index if not exists profiles_username_trgm_idx
  on public.profiles using gin (username gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- search_profiles: the readable profiles whose username is a substring of, or
-- trigram-similar to, the query — nearest first.
--
-- Security INVOKER (the default): runs as the caller, so the `profiles` RLS
-- policy (readable by authenticated users — see 0002_rls_hardening.sql) still
-- applies and this can never expose a row the caller couldn't already select.
-- ---------------------------------------------------------------------------
create or replace function public.search_profiles(p_query text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_id text,
  vehicle_type text
)
language sql stable set search_path = public as $$
  with q as (select btrim(coalesce(p_query, '')) as term)
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_id,
    p.vehicle_type
  from public.profiles p, q
  where char_length(q.term) >= 2
    and p.id <> auth.uid()
    and (
      -- Literal substring (strpos, not LIKE, so % and _ in the query are not
      -- treated as wildcards).
      strpos(lower(p.username), lower(q.term)) > 0
      -- Or close enough by trigram similarity (the `%` operator uses
      -- pg_trgm.similarity_threshold, default 0.3).
      or p.username % q.term
    )
  order by
    (strpos(lower(p.username), lower(q.term)) > 0) desc,
    similarity(p.username, q.term) desc,
    p.username
  limit 20;
$$;

-- ---------------------------------------------------------------------------
-- Deny anon/PUBLIC; keep authenticated (the app) able to call it. Same
-- treatment as 0008 / 0015.
-- ---------------------------------------------------------------------------
revoke execute on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated, service_role;
