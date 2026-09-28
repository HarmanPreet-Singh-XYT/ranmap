-- ---------------------------------------------------------------------------
-- Ranmap migration 0029: shareable read-only "watch my ride" links.
--
-- A trip's creator can mint a public link anyone can open (no account) to
-- follow the trip's live position on a simple page. The token is the
-- capability: it's long and random, only the creator can create or revoke it,
-- and the server (service role) validates it before serving any data.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

create table if not exists public.trip_shares (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  -- 32 hex chars from a UUID; unguessable enough for a read-only link.
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint trip_shares_token_len_chk check (char_length(token) = 32)
);

create index if not exists trip_shares_trip_idx on public.trip_shares (trip_id);

alter table public.trip_shares enable row level security;

-- Only the share's creator manages it, and only the trip's creator may create one.
drop policy if exists "trip_shares_select_creator" on public.trip_shares;
create policy "trip_shares_select_creator" on public.trip_shares
  for select using (auth.uid() = created_by);

drop policy if exists "trip_shares_insert_creator" on public.trip_shares;
create policy "trip_shares_insert_creator" on public.trip_shares
  for insert with check (
    auth.uid() = created_by and public.is_trip_creator(trip_id, auth.uid())
  );

drop policy if exists "trip_shares_delete_creator" on public.trip_shares;
create policy "trip_shares_delete_creator" on public.trip_shares
  for delete using (auth.uid() = created_by);
