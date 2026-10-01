-- ---------------------------------------------------------------------------
-- Ranmap migration 0053: several images per expense, plan-gated.
--
-- An expense carried a single `receipt_path` (0052). "Add another with +" is
-- one-to-many, so the attachment becomes a child row instead: the free tier is
-- then simply "the cap is one" rather than a second code path, and the count is
-- enforced the same way every other capped collection in this schema is.
--
--   * `trip_expense_media` — one row per image, cascading with its expense.
--   * `plan_limit('expense_media')` — free 1, Pro 10, Extreme 25.
--   * `enforce_expense_media_limit()` — a BEFORE INSERT trigger that counts the
--     expense's images and raises the usual 'Ranmap Pro required: …' /
--     'Plan limit reached: …' markers, which both clients already turn into a
--     paywall.
--   * the `map-media` read policy now authorizes through this table, so an
--     expense's images are visible to the whole trip exactly like its photos.
--
-- Safe to run whether or not 0051 was applied: any existing `receipt_path` is
-- backfilled first (guarded on the column still existing), then dropped.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- The attachments themselves.
-- ---------------------------------------------------------------------------
create table if not exists public.trip_expense_media (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.trip_expenses (id) on delete cascade,
  storage_path text not null,
  -- Display order, so the strip shows the images in the order they were added.
  position int not null default 0,
  created_at timestamptz not null default now(),
  unique (expense_id, storage_path)
);
create index if not exists trip_expense_media_expense_idx on public.trip_expense_media (expense_id);
alter table public.trip_expense_media enable row level security;
-- Mirrors the parent expense's rules, joined through it: anyone on the trip can
-- see an expense, so anyone on the trip can see its bill. Only the person who
-- logged the expense may attach to it or take an attachment away.
drop policy if exists "trip_expense_media_select_participant" on public.trip_expense_media;
create policy "trip_expense_media_select_participant" on public.trip_expense_media for
select using (
    exists (
      select 1
      from public.trip_expenses e
      where e.id = expense_id
        and public.is_trip_participant(e.trip_id, auth.uid())
    )
  );
drop policy if exists "trip_expense_media_insert_owner" on public.trip_expense_media;
create policy "trip_expense_media_insert_owner" on public.trip_expense_media for
insert with check (
    exists (
      select 1
      from public.trip_expenses e
      where e.id = expense_id
        and e.user_id = auth.uid()
        and public.is_trip_participant(e.trip_id, auth.uid())
    )
  );
drop policy if exists "trip_expense_media_delete_owner" on public.trip_expense_media;
create policy "trip_expense_media_delete_owner" on public.trip_expense_media for delete using (
  exists (
    select 1
    from public.trip_expenses e
    where e.id = expense_id
      and e.user_id = auth.uid()
  )
);
-- No UPDATE policy: an attachment is added or removed, never edited.
-- ---------------------------------------------------------------------------
-- The `map-media` read policy: an expense's images join through the new table.
-- ---------------------------------------------------------------------------
drop policy if exists "map_media_read_visible" on storage.objects;
create policy "map_media_read_visible" on storage.objects for
select using (
    bucket_id = 'map-media'
    and (
      (storage.foldername(name)) [1] = auth.uid()::text
      or exists (
        select 1
        from public.map_posts p
        where p.storage_path = storage.objects.name
          and public.can_view_map_post(p.id, auth.uid())
      )
      or exists (
        select 1
        from public.trip_expense_media m
          join public.trip_expenses e on e.id = m.expense_id
        where m.storage_path = storage.objects.name
          and public.is_trip_participant(e.trip_id, auth.uid())
      )
    )
  );
-- ---------------------------------------------------------------------------
-- Bring an already-applied 0052 across, then drop the column it used.
--
-- Order matters: this MUST come after the read policy above. That policy used to
-- reference `trip_expenses.receipt_path`, and Postgres refuses to drop a column
-- an existing policy depends on ("cannot drop column ... because other objects
-- depend on it"). Replacing the policy first — with the version that joins
-- through `trip_expense_media` — releases the dependency, so the column can go.
-- ---------------------------------------------------------------------------
do $$ begin if exists (
  select 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'trip_expenses'
    and column_name = 'receipt_path'
) then
insert into public.trip_expense_media (expense_id, storage_path)
select e.id,
  e.receipt_path
from public.trip_expenses e
where e.receipt_path is not null on conflict (expense_id, storage_path) do nothing;
alter table public.trip_expenses drop column if exists receipt_path;
end if;
end;
$$;
-- ---------------------------------------------------------------------------
-- The limit key. Re-created in full (matching 0034) so an unknown key still
-- raises rather than returning NULL — a `count >= NULL` would read as no cap.
-- ---------------------------------------------------------------------------
create or replace function public.plan_limit(p_key text) returns int language plpgsql immutable as $$
declare v_limit int;
begin v_limit := case
  p_key
  when 'trips' then 3
  when 'group_members' then 6
  when 'map_posts' then 25
  when 'documents' then 1
  when 'route_templates' then 1
  when 'expense_media' then 1
  when 'trips_pro' then 100
  when 'group_members_pro' then 100
  when 'map_posts_pro' then 5000
  when 'documents_pro' then 100
  when 'route_templates_pro' then 100
  when 'expense_media_pro' then 10
  when 'trips_extreme' then 250
  when 'group_members_extreme' then 250
  when 'map_posts_extreme' then 20000
  when 'documents_extreme' then 500
  when 'route_templates_extreme' then 500
  when 'expense_media_extreme' then 25
end;
if v_limit is null then raise exception 'unknown plan limit key: %',
p_key;
end if;
return v_limit;
end;
$$;
-- ---------------------------------------------------------------------------
-- The cap. Counted per expense (not per account), because the allowance is
-- "images on this expense". The tier is the expense owner's — they are the only
-- one who can attach to it (see the insert policy above).
-- ---------------------------------------------------------------------------
create or replace function public.enforce_expense_media_limit() returns trigger language plpgsql security definer
set search_path = public as $$
declare v_owner uuid;
v_extreme boolean;
v_pro boolean;
v_limit int;
v_count int;
begin
select e.user_id into v_owner
from public.trip_expenses e
where e.id = new.expense_id;
-- A missing expense is the foreign key's problem, not ours.
if v_owner is null then return new;
end if;
-- An attachment that is already there needs no capacity. This matters for the
-- replay of an offline-queued expense: it re-inserts its images with
-- `on conflict do nothing`, and a BEFORE INSERT trigger runs *before* that
-- conflict is resolved — so without this the replay of a full expense would be
-- refused and the queue entry would never drain.
if exists (
  select 1
  from public.trip_expense_media m
  where m.expense_id = new.expense_id
    and m.storage_path = new.storage_path
) then return new;
end if;
v_extreme := public.is_extreme(v_owner);
v_pro := public.is_pro(v_owner);
v_limit := public.plan_limit(
  case
    when v_extreme then 'expense_media_extreme'
    when v_pro then 'expense_media_pro'
    else 'expense_media'
  end
);
-- Serialize concurrent inserts on the same expense, so two attachments added
-- at once can't both slip past the cap.
perform pg_advisory_xact_lock(
  hashtext('trip_expense_media:' || new.expense_id::text)
);
select count(*) into v_count
from public.trip_expense_media m
where m.expense_id = new.expense_id;
if v_count >= v_limit then if v_extreme then raise exception 'Plan limit reached: your Extreme plan includes up to % images per expense.',
v_limit using errcode = 'P0001';
elsif v_pro then raise exception 'Plan limit reached: your Pro plan includes up to % images per expense. Upgrade to Extreme for more.',
v_limit using errcode = 'P0001';
end if;
raise exception 'Ranmap Pro required: free expenses can carry % image. Upgrade to attach more.',
v_limit using errcode = 'P0001';
end if;
return new;
end;
$$;
drop trigger if exists trip_expense_media_free_limit on public.trip_expense_media;
create trigger trip_expense_media_free_limit before
insert on public.trip_expense_media for each row execute function public.enforce_expense_media_limit();