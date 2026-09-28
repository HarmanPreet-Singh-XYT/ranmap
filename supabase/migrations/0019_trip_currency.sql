-- ---------------------------------------------------------------------------
-- Ranmap migration 0019: one currency per trip.
--
-- `trip_expenses.currency` existed but the app never set it (every row was the
-- 'USD' default) and the ledger labelled its totals from `expenses.first` —
-- one arbitrary row. That silently sums mixed currencies once a non-USD value
-- can appear. Track the currency on the trip instead, so the ledger and the
-- fuel figures have one deliberate source of truth.
--
-- `create_trip` gains `p_currency`; the old 11-arg overload is dropped so
-- PostgREST's named-argument resolution stays unambiguous.
-- ---------------------------------------------------------------------------

alter table public.trips
  add column if not exists currency text not null default 'USD';

alter table public.trips drop constraint if exists trips_currency_chk;
alter table public.trips
  add constraint trips_currency_chk check (char_length(currency) = 3);

drop function if exists public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text, uuid
);

create or replace function public.create_trip(
  p_title text,
  p_group_id uuid default null,
  p_scheduled_start timestamptz default null,
  p_origin_name text default null,
  p_origin_lat double precision default null,
  p_origin_lng double precision default null,
  p_destination_name text default null,
  p_destination_lat double precision default null,
  p_destination_lng double precision default null,
  p_route_polyline text default null,
  p_user uuid default null,
  p_currency text default 'USD'
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid;
  v_trip public.trips;
begin
  if p_user is not null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'not authorized to specify a user';
  end if;

  v_uid := coalesce(p_user, auth.uid());
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_title), '') = '' then
    raise exception 'title is required';
  end if;
  if p_group_id is not null and not public.is_group_member(p_group_id, v_uid) then
    raise exception 'not a member of the target group';
  end if;

  insert into public.trips (
    created_by, title, group_id, scheduled_start, currency,
    origin_name, origin_point, destination_name, destination_point, route_polyline
  )
  values (
    v_uid, btrim(p_title), p_group_id, p_scheduled_start,
    coalesce(nullif(btrim(upper(p_currency)), ''), 'USD'),
    p_origin_name,
    case when p_origin_lat is not null and p_origin_lng is not null
      then ST_SetSRID(ST_MakePoint(p_origin_lng, p_origin_lat), 4326)::geography end,
    p_destination_name,
    case when p_destination_lat is not null and p_destination_lng is not null
      then ST_SetSRID(ST_MakePoint(p_destination_lng, p_destination_lat), 4326)::geography end,
    p_route_polyline
  )
  returning * into v_trip;

  insert into public.trip_members (trip_id, user_id, invite_status, joined_at)
  values (v_trip.id, v_uid, 'accepted', now());

  if p_scheduled_start is not null and p_scheduled_start > now() then
    insert into public.scheduled_trips (trip_id, scheduled_for, created_by_ai)
    select v_trip.id, p_scheduled_start, false
    where not exists (
      select 1 from public.scheduled_trips st where st.trip_id = v_trip.id
    );
  end if;

  return v_trip;
end;
$$;

revoke execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text, uuid, text
) from public, anon;
grant execute on function public.create_trip(
  text, uuid, timestamptz, text, double precision, double precision,
  text, double precision, double precision, text, uuid, text
) to authenticated, service_role;
