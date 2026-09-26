-- ---------------------------------------------------------------------------
-- Ranmap migration 0015: convoy consensus voting on a proposed stop.
--
-- A trip member (or the AI copilot) *proposes* a stop; the trip's members
-- approve or reject it in `stop_votes`; once a strict majority of the trip's
-- members approve, the proposal is promoted into a real `trip_stops` row
-- (appended to the end of the itinerary). Every tally is derived from real
-- `stop_votes` rows on read — nothing is stored pre-computed, so the counts
-- can never drift from the votes.
--
-- Additive only: two new tables, their RLS, and three RPCs. Existing tables
-- and functions are untouched.
--
-- Safe to re-run (tables are `if not exists`, policies are dropped before
-- being recreated, and functions are `create or replace`).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- stop_proposals: one row per proposed stop.
-- ---------------------------------------------------------------------------
create table if not exists public.stop_proposals (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  note text,
  lat double precision,
  lng double precision,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  constraint stop_proposals_status_chk check (status in ('open', 'approved', 'rejected')),
  -- Same bounds trip_stops enforces on its own name / notes (see
  -- 0012_text_length_limits.sql), so a promoted proposal always fits the row
  -- it's copied into.
  constraint stop_proposals_name_len_chk check (char_length(name) between 1 and 60),
  constraint stop_proposals_note_len_chk check (note is null or char_length(note) <= 500)
);

-- ---------------------------------------------------------------------------
-- stop_votes: the caller's single vote on a proposal (primary key enforces one
-- vote per member per proposal; re-voting updates that row).
-- ---------------------------------------------------------------------------
create table if not exists public.stop_votes (
  proposal_id uuid not null references public.stop_proposals (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  approve boolean not null,
  created_at timestamptz not null default now(),
  primary key (proposal_id, user_id)
);

create index if not exists stop_proposals_trip_idx on public.stop_proposals (trip_id);
create index if not exists stop_votes_proposal_idx on public.stop_votes (proposal_id);

alter table public.stop_proposals enable row level security;
alter table public.stop_votes enable row level security;

-- ---------------------------------------------------------------------------
-- RLS: reads are for any trip member; proposals are written by their creator
-- (or a member promoting); votes are the voter's own. Mirrors the helper-free
-- membership predicates used on trip_stops in 0002_rls_hardening.sql.
-- ---------------------------------------------------------------------------
drop policy if exists "stop_proposals_select_member" on public.stop_proposals;
create policy "stop_proposals_select_member" on public.stop_proposals
  for select using (
    exists (
      select 1 from public.trip_members m
      where m.trip_id = stop_proposals.trip_id and m.user_id = auth.uid()
    )
  );

drop policy if exists "stop_proposals_insert_member" on public.stop_proposals;
create policy "stop_proposals_insert_member" on public.stop_proposals
  for insert with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.trip_members m
      where m.trip_id = stop_proposals.trip_id and m.user_id = auth.uid()
    )
  );

-- The proposer may edit their proposal; any trip member may update it (a
-- member promoting it via the vote RPC). Writes that point at another trip
-- are rejected by the same membership check.
drop policy if exists "stop_proposals_update_creator_or_member" on public.stop_proposals;
create policy "stop_proposals_update_creator_or_member" on public.stop_proposals
  for update using (
    created_by = auth.uid()
    or exists (
      select 1 from public.trip_members m
      where m.trip_id = stop_proposals.trip_id and m.user_id = auth.uid()
    )
  ) with check (
    created_by = auth.uid()
    or exists (
      select 1 from public.trip_members m
      where m.trip_id = stop_proposals.trip_id and m.user_id = auth.uid()
    )
  );

-- Votes are visible to anyone on the proposal's trip.
drop policy if exists "stop_votes_select_member" on public.stop_votes;
create policy "stop_votes_select_member" on public.stop_votes
  for select using (
    exists (
      select 1 from public.stop_proposals p
      join public.trip_members m on m.trip_id = p.trip_id
      where p.id = stop_votes.proposal_id and m.user_id = auth.uid()
    )
  );

-- A member may only cast their own vote, and only on a proposal for a trip
-- they belong to.
drop policy if exists "stop_votes_insert_self" on public.stop_votes;
create policy "stop_votes_insert_self" on public.stop_votes
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.stop_proposals p
      join public.trip_members m on m.trip_id = p.trip_id
      where p.id = stop_votes.proposal_id and m.user_id = auth.uid()
    )
  );

drop policy if exists "stop_votes_update_self" on public.stop_votes;
create policy "stop_votes_update_self" on public.stop_votes
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "stop_votes_delete_self" on public.stop_votes;
create policy "stop_votes_delete_self" on public.stop_votes
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- propose_stop: create an open proposal for a stop. Any member of the trip may
-- propose (not just the creator), matching the convoy-consensus intent.
-- ---------------------------------------------------------------------------
create or replace function public.propose_stop(
  p_trip uuid,
  p_name text,
  p_note text default null,
  p_lat double precision default null,
  p_lng double precision default null
)
returns public.stop_proposals
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prop public.stop_proposals;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip and m.user_id = v_uid
  ) then
    raise exception 'not a member of this trip';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;

  insert into public.stop_proposals (trip_id, created_by, name, note, lat, lng)
  values (p_trip, v_uid, btrim(p_name), p_note, p_lat, p_lng)
  returning * into v_prop;

  return v_prop;
end;
$$;

-- ---------------------------------------------------------------------------
-- vote_stop_proposal: upsert the caller's vote, then promote the proposal when
-- a strict majority of the trip's members have approved.
--
-- Majority rule: approvals > half of the trip's members, computed from the
-- real `trip_members` rows for the trip — i.e. `approvals * 2 > member_count`.
-- (See the note at the end of this file about what "member" counts here.)
--
-- Promotion sets status = 'approved' and appends ONE real `trip_stops` row
-- (kind 'custom', at the end of the order). The `status = 'open'` guard on the
-- update, plus row locking, makes double-promotion impossible even if two
-- votes land at once.
-- ---------------------------------------------------------------------------
create or replace function public.vote_stop_proposal(
  p_proposal uuid,
  p_approve boolean
)
returns public.stop_proposals
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prop public.stop_proposals;
  v_members bigint;
  v_approvals bigint;
  v_next_sort integer;
  v_point geography;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_prop from public.stop_proposals where id = p_proposal;
  if not found then
    raise exception 'proposal not found';
  end if;

  if not exists (
    select 1 from public.trip_members m
    where m.trip_id = v_prop.trip_id and m.user_id = v_uid
  ) then
    raise exception 'not a member of this trip';
  end if;

  -- One vote per member per proposal; re-voting overwrites the previous one.
  insert into public.stop_votes (proposal_id, user_id, approve)
  values (p_proposal, v_uid, coalesce(p_approve, false))
  on conflict (proposal_id, user_id) do update
    set approve = excluded.approve, created_at = now();

  -- Recompute the tally from the real rows (never from a cached counter).
  select count(*) into v_members
  from public.trip_members m where m.trip_id = v_prop.trip_id;

  select count(*) into v_approvals
  from public.stop_votes v where v.proposal_id = p_proposal and v.approve;

  if v_prop.status = 'open' and v_approvals * 2 > v_members then
    -- Prefer the proposal's own coordinates; when none were given, fall back
    -- to the trip's planned destination/origin so the stop still has a real,
    -- route-derived point (trip_stops.point is NOT NULL). If even that is
    -- absent, the vote is still recorded but the proposal is left open.
    v_point := case
      when v_prop.lat is not null and v_prop.lng is not null
        then ST_SetSRID(ST_MakePoint(v_prop.lng, v_prop.lat), 4326)::geography
      else (
        select coalesce(t.destination_point, t.origin_point)
        from public.trips t where t.id = v_prop.trip_id
      )
    end;

    if v_point is not null then
      update public.stop_proposals
      set status = 'approved'
      where id = p_proposal and status = 'open'
      returning * into v_prop;

      -- `found` is true only for the single transaction that flipped it.
      if found then
        -- Append at the end of the trip's current ordering.
        select coalesce(max(s.sort_order), -1) + 1 into v_next_sort
        from public.trip_stops s where s.trip_id = v_prop.trip_id;

        insert into public.trip_stops (trip_id, created_by, kind, name, point, notes, sort_order)
        values (
          v_prop.trip_id, v_prop.created_by, 'custom', v_prop.name, v_point, v_prop.note, v_next_sort
        );
      end if;
    end if;
  end if;

  return v_prop;
end;
$$;

-- ---------------------------------------------------------------------------
-- trip_proposals: the client's read model — each proposal on a trip with its
-- live approvals / rejections / the caller's own vote / the member count, all
-- derived from the underlying rows.
-- ---------------------------------------------------------------------------
create or replace function public.trip_proposals(p_trip uuid)
returns table (
  id uuid,
  trip_id uuid,
  created_by uuid,
  name text,
  note text,
  lat double precision,
  lng double precision,
  status text,
  created_at timestamptz,
  approvals bigint,
  rejections bigint,
  my_vote boolean,
  member_count bigint
)
language sql stable security definer set search_path = public as $$
  select
    p.id,
    p.trip_id,
    p.created_by,
    p.name,
    p.note,
    p.lat,
    p.lng,
    p.status,
    p.created_at,
    (select count(*) from public.stop_votes v
      where v.proposal_id = p.id and v.approve) as approvals,
    (select count(*) from public.stop_votes v
      where v.proposal_id = p.id and not v.approve) as rejections,
    (select v.approve from public.stop_votes v
      where v.proposal_id = p.id and v.user_id = auth.uid()) as my_vote,
    (select count(*) from public.trip_members m
      where m.trip_id = p.trip_id) as member_count
  from public.stop_proposals p
  where p.trip_id = p_trip
    and exists (
      select 1 from public.trip_members m
      where m.trip_id = p_trip and m.user_id = auth.uid()
    )
  order by p.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Deny anon/PUBLIC; keep authenticated (the app) and service_role (the
-- AI copilot server) able to call them. Same treatment as 0008.
-- ---------------------------------------------------------------------------
revoke execute on function public.propose_stop(uuid, text, text, double precision, double precision)
  from public, anon;
grant execute on function public.propose_stop(uuid, text, text, double precision, double precision)
  to authenticated, service_role;

revoke execute on function public.vote_stop_proposal(uuid, boolean) from public, anon;
grant execute on function public.vote_stop_proposal(uuid, boolean) to authenticated, service_role;

revoke execute on function public.trip_proposals(uuid) from public, anon;
grant execute on function public.trip_proposals(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- "Member" here is any row in trip_members for the trip (accepted OR still
-- invited) — the same population the existing RLS predicates treat as a trip
-- member — so the majority threshold and the "can read / can vote" rule all
-- line up. If the product ever wants a majority over *accepted* members only,
-- add `and m.invite_status = 'accepted'` to the two `v_members` / `member_count`
-- counts without touching anything else.
-- ---------------------------------------------------------------------------
