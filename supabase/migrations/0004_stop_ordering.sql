-- Ranmap migration 0004: manual stop ordering
--
-- trip_stops had no user-controlled ordering — the UI sorted by
-- planned_arrival, so an unplanned/ad-hoc stop (no arrival time) had no
-- stable position and reordering wasn't possible. Adds a sort_order column,
-- backfilled by existing planned_arrival/created_at order, plus an RPC to
-- reorder atomically (a drag-and-drop reorder is many stops changing
-- position at once; doing it as N separate updates risks a partial/racy
-- result if it's interrupted).
--
-- Safe to re-run.

alter table public.trip_stops add column if not exists sort_order integer;

with ordered as (
  select id, row_number() over (
    partition by trip_id
    order by planned_arrival nulls last, created_at
  ) - 1 as rn
  from public.trip_stops
  where sort_order is null
)
update public.trip_stops s
set sort_order = ordered.rn
from ordered
where s.id = ordered.id;

alter table public.trip_stops alter column sort_order set not null;
alter table public.trip_stops alter column sort_order set default 0;

create index if not exists trip_stops_trip_sort_idx
  on public.trip_stops (trip_id, sort_order);

-- ---------------------------------------------------------------------------
-- Atomically apply a full reorder for one trip's stops. p_stop_ids must be
-- the complete, reordered set of stop ids for that trip; each stop's new
-- sort_order is its index in the array. Only a trip participant may reorder.
-- ---------------------------------------------------------------------------
create or replace function public.reorder_trip_stops(p_trip uuid, p_stop_ids uuid[])
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_trip_participant(p_trip, auth.uid()) then
    raise exception 'not a participant of this trip';
  end if;

  if exists (
    select 1 from public.trip_stops
    where trip_id = p_trip and id <> all (p_stop_ids)
  ) then
    raise exception 'p_stop_ids must include every stop on the trip';
  end if;

  update public.trip_stops s
  set sort_order = ord.idx
  from unnest(p_stop_ids) with ordinality as ord(id, idx)
  where s.id = ord.id and s.trip_id = p_trip;
end;
$$;

grant execute on function public.reorder_trip_stops(uuid, uuid[]) to authenticated;
