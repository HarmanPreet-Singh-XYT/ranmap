-- ---------------------------------------------------------------------------
-- Ranmap migration 0028: planning + convoy-status follow-ups.
--
--   * Quick convoy statuses: the group alert kinds grow from sos/regroup/
--     arrived/departed to include wait / stopping / fuel, so a rider can fire
--     a one-tap "wait up", "I'm stopping" or "need fuel" to the crew.
--   * `trip_checklist_items` — a shared per-trip packing/prep checklist.
--   * `route_templates` — a personal, reusable saved route (origin →
--     destination + polyline) so a familiar drive doesn't have to be re-planned.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Quick convoy statuses: widen the alert-kind allowlist.
-- ---------------------------------------------------------------------------
alter table public.group_alerts drop constraint if exists group_alerts_kind_chk;
alter table public.group_alerts
  add constraint group_alerts_kind_chk
  check (kind in ('sos', 'regroup', 'arrived', 'departed', 'wait', 'stopping', 'fuel'));

-- ---------------------------------------------------------------------------
-- 2. Trip checklist. Visible and editable by any trip participant (it's a
--    shared "who's bringing what" board).
-- ---------------------------------------------------------------------------
create table if not exists public.trip_checklist_items (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  label text not null,
  done boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint trip_checklist_items_label_len_chk check (char_length(label) between 1 and 80)
);

create index if not exists trip_checklist_items_trip_idx
  on public.trip_checklist_items (trip_id, sort_order);

alter table public.trip_checklist_items enable row level security;

drop policy if exists "trip_checklist_select_participant" on public.trip_checklist_items;
create policy "trip_checklist_select_participant" on public.trip_checklist_items
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_checklist_insert_participant" on public.trip_checklist_items;
create policy "trip_checklist_insert_participant" on public.trip_checklist_items
  for insert with check (
    public.is_trip_participant(trip_id, auth.uid()) and auth.uid() = created_by
  );

drop policy if exists "trip_checklist_update_participant" on public.trip_checklist_items;
create policy "trip_checklist_update_participant" on public.trip_checklist_items
  for update using (public.is_trip_participant(trip_id, auth.uid()))
  with check (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_checklist_delete_participant" on public.trip_checklist_items;
create policy "trip_checklist_delete_participant" on public.trip_checklist_items
  for delete using (public.is_trip_participant(trip_id, auth.uid()));

-- trip_id / created_by must not be reassigned (mirrors the trips treatment).
revoke update on public.trip_checklist_items from anon, authenticated;
grant update (label, done, sort_order) on public.trip_checklist_items to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Personal route templates. Owner-only (a private library of saved drives).
-- ---------------------------------------------------------------------------
create table if not exists public.route_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  origin_name text,
  origin_point geography(point, 4326),
  destination_name text,
  destination_point geography(point, 4326),
  route_polyline text,
  created_at timestamptz not null default now(),
  constraint route_templates_name_len_chk check (char_length(name) between 1 and 60),
  constraint route_templates_place_name_len_chk check (
    (origin_name is null or char_length(origin_name) <= 120)
    and (destination_name is null or char_length(destination_name) <= 120)
  ),
  constraint route_templates_polyline_len_chk check (
    route_polyline is null or char_length(route_polyline) <= 200000
  )
);

create index if not exists route_templates_user_idx
  on public.route_templates (user_id, created_at desc);

alter table public.route_templates enable row level security;

drop policy if exists "route_templates_owner" on public.route_templates;
create policy "route_templates_owner" on public.route_templates
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
