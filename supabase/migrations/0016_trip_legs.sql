-- ---------------------------------------------------------------------------
-- Ranmap migration 0016: trip legs (multi-modal trips).
--
-- A trip used to be single-mode: one planned `trips.route_polyline` plus a
-- list of `trip_stops`, with nothing to express "drive A→B, then switch to the
-- bike for B→C". `trip_legs` models each segment between consecutive
-- waypoints (the trip origin, then the stops in `sort_order`) as its own leg
-- with a mode, geometry and — when a real route was measured — a distance and
-- duration.
--
-- Additive only: one new table, its RLS and indexes. Nothing existing is
-- changed; the client writes legs directly through PostgREST (no RPC needed),
-- subject to the membership RLS below.
--
-- Safe to re-run (the table is `if not exists`, policies are dropped before
-- being recreated).
-- ---------------------------------------------------------------------------

create table if not exists public.trip_legs (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  -- 0-based index of the stop this leg travels *to*: seq 0 is the leg from the
  -- trip origin to the first stop, and seq N (N >= 1) is the leg from the
  -- (N-1)th stop to the Nth.
  seq integer not null,
  -- The stop this leg arrives at. Mirrors `seq` (seq 0's leg arrives at the
  -- first stop, and so on) but survives a reorder/delete as a real link to the
  -- stop, so the leg follows the stop it describes. Nullable: a whole-trip
  -- origin→destination leg has no destination stop. `on delete cascade` so
  -- deleting a stop removes the leg arriving at it.
  to_stop_id uuid references public.trip_stops (id) on delete cascade,
  -- Same value set as `profiles.vehicle_type` (see 0007_security_fixes.sql).
  mode text not null,
  -- Measured only when a route was actually returned; left null otherwise, so
  -- a leg never carries an invented distance/duration.
  distance_m double precision,
  duration_s double precision,
  route_polyline text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint trip_legs_mode_chk
    check (mode in ('car', 'bike', 'scooter', 'suv', 'other')),
  constraint trip_legs_seq_nonneg_chk check (seq >= 0),
  constraint trip_legs_distance_nonneg_chk check (distance_m is null or distance_m >= 0),
  constraint trip_legs_duration_nonneg_chk check (duration_s is null or duration_s >= 0),
  -- Mirrors the bound trips.route_polyline carries (0012_text_length_limits.sql).
  constraint trip_legs_polyline_len_chk
    check (route_polyline is null or char_length(route_polyline) <= 200000),
  -- One leg per position along a trip's waypoint chain.
  unique (trip_id, seq)
);

create index if not exists trip_legs_trip_idx on public.trip_legs (trip_id);
create index if not exists trip_legs_to_stop_idx on public.trip_legs (to_stop_id);
create index if not exists trip_legs_created_by_idx on public.trip_legs (created_by);

alter table public.trip_legs enable row level security;

-- ---------------------------------------------------------------------------
-- RLS: readable by any participant of the trip; inserted/updated/deleted by a
-- participant (the client writes legs directly). Mirrors the trip_stops
-- treatment in 0002_rls_hardening.sql — `is_trip_participant` is creator-or-
-- accepted-member, the same population that can read the stops a leg joins.
-- ---------------------------------------------------------------------------
drop policy if exists "trip_legs_select_member" on public.trip_legs;
create policy "trip_legs_select_member" on public.trip_legs
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_legs_insert_member" on public.trip_legs;
create policy "trip_legs_insert_member" on public.trip_legs
  for insert with check (
    auth.uid() = created_by and public.is_trip_participant(trip_id, auth.uid())
  );

drop policy if exists "trip_legs_update_member" on public.trip_legs;
create policy "trip_legs_update_member" on public.trip_legs
  for update using (public.is_trip_participant(trip_id, auth.uid()))
  with check (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_legs_delete_member" on public.trip_legs;
create policy "trip_legs_delete_member" on public.trip_legs
  for delete using (public.is_trip_participant(trip_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- Table privileges: the app (authenticated) reads/writes legs directly; anon
-- has no business with trip data. RLS still gates every row on membership.
-- ---------------------------------------------------------------------------
revoke all on public.trip_legs from anon;
grant select, insert, update, delete on public.trip_legs to authenticated;
