-- Ranmap migration 0007: security & integrity fixes
--
-- Closes holes found in a follow-up audit:
--   * chat_messages allowed a row to target BOTH a trip and a group, letting a
--     trip participant inject a message into any group's channel.
--   * profiles.phone_verified was only guarded on UPDATE; a client could set it
--     on INSERT and claim a verified number without Twilio.
--   * trip_stops had no column-level UPDATE grants, so a stop's owner could
--     reassign trip_id and inject a stop into any trip.
--   * create_trip accepted an arbitrary group_id; update_trip_route wiped
--     coordinates on NULL and did no range checks.
--   * map_posts.storage_path wasn't required to live under the uploader's
--     folder, enabling a cross-user media read via the storage policy.
--   * a 'blocked' friendship could be deleted by the blocked party.
--   * enum-like / numeric columns had no CHECK constraints.
--   * SECURITY DEFINER helpers were executable by PUBLIC/anon.
--   * missing FK / policy / GiST indexes.
--   * trip_stats had no DELETE policy.
--   * the scheduler did a non-atomic flip-then-delete.
--
-- Safe to re-run (policies/constraints/functions are dropped or guarded).

-- ---------------------------------------------------------------------------
-- chat_messages: exactly one channel per row, and the insert policy must
-- enforce the same (the OR let a row satisfy the trip branch while carrying a
-- foreign group_id).
-- ---------------------------------------------------------------------------
alter table public.chat_messages
  drop constraint if exists chat_messages_one_channel_chk;
alter table public.chat_messages
  add constraint chat_messages_one_channel_chk
  check ((trip_id is not null) <> (group_id is not null)) not valid;

drop policy if exists "chat_messages_insert_sender" on public.chat_messages;
create policy "chat_messages_insert_sender" on public.chat_messages
  for insert with check (
    auth.uid() = sender_id
    and (trip_id is not null) <> (group_id is not null)
    and (
      (trip_id is not null and public.is_trip_participant(trip_id, auth.uid()))
      or (group_id is not null and public.is_group_member(group_id, auth.uid()))
    )
  );

-- ---------------------------------------------------------------------------
-- profiles: narrow the INSERT grant (phone_verified must not be client-writable
-- on insert) and add a BEFORE INSERT guard as defence in depth.
-- ---------------------------------------------------------------------------
revoke insert on public.profiles from anon, authenticated;
grant insert (id, username, display_name, avatar_id, vehicle_type, phone_number, socials)
  on public.profiles to anon, authenticated;

create or replace function public.reset_phone_verified_on_insert()
returns trigger language plpgsql set search_path = public as $$
begin
  if auth.role() <> 'service_role' then
    new.phone_verified := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reset_phone_verified_insert on public.profiles;
create trigger trg_reset_phone_verified_insert
  before insert on public.profiles
  for each row execute function public.reset_phone_verified_on_insert();

-- Pin search_path on the existing update-time trigger too.
create or replace function public.reset_phone_verified_on_change()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.phone_number is distinct from old.phone_number
     and auth.role() <> 'service_role' then
    new.phone_verified := false;
  end if;
  return new;
end;
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- trip_stops: forbid reassigning trip_id / created_by via column-level grants
-- (mirrors the trips / trip_members treatment in 0002).
-- ---------------------------------------------------------------------------
revoke update on public.trip_stops from anon, authenticated;
grant update (kind, name, point, planned_arrival, actual_arrival, actual_departure, notes, sort_order)
  on public.trip_stops to anon, authenticated;

-- ---------------------------------------------------------------------------
-- friendships: a block can't be undone by deleting the row as the requester.
-- ---------------------------------------------------------------------------
drop policy if exists "friendships_delete_participant" on public.friendships;
create policy "friendships_delete_participant" on public.friendships
  for delete using (
    (auth.uid() = requester_id or auth.uid() = addressee_id)
    and not (status = 'blocked' and auth.uid() = requester_id)
  );

-- ---------------------------------------------------------------------------
-- map_posts: the stored path must live under the uploader's own folder
-- (otherwise the storage read policy could be tricked into exposing another
-- user's private object).
-- ---------------------------------------------------------------------------
drop policy if exists "map_posts_insert_self" on public.map_posts;
create policy "map_posts_insert_self" on public.map_posts
  for insert with check (
    auth.uid() = user_id
    and (trip_id is null or public.is_trip_participant(trip_id, auth.uid()))
    and (storage.foldername(storage_path))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- map_post_shares: exactly one target.
-- ---------------------------------------------------------------------------
alter table public.map_post_shares
  drop constraint if exists map_post_shares_one_target_chk;
alter table public.map_post_shares
  add constraint map_post_shares_one_target_chk
  check ((shared_with_user is not null) <> (shared_with_group is not null)) not valid;

-- ---------------------------------------------------------------------------
-- trip_stats: allow removing your own rollup.
-- ---------------------------------------------------------------------------
drop policy if exists "trip_stats_delete_self" on public.trip_stats;
create policy "trip_stats_delete_self" on public.trip_stats
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Enum-like / numeric CHECK constraints (NOT VALID so existing rows can't
-- block the migration; new writes are still enforced).
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('profiles',        'profiles_vehicle_type_chk',      $q$vehicle_type in ('car','bike','scooter','suv','other')$q$),
      ('friendships',     'friendships_status_chk',         $q$status in ('pending','accepted','blocked','declined')$q$),
      ('group_members',   'group_members_role_chk',         $q$role in ('owner','admin','member')$q$),
      ('trips',           'trips_status_chk',               $q$status in ('planned','active','completed','cancelled')$q$),
      ('trip_members',    'trip_members_status_chk',        $q$invite_status in ('invited','accepted','declined')$q$),
      ('trip_stops',      'trip_stops_kind_chk',            $q$kind in ('food','scenery','fuel','rest','custom')$q$),
      ('trip_expenses',   'trip_expenses_category_chk',     $q$category in ('fuel','food','toll','lodging','other')$q$),
      ('trip_expenses',   'trip_expenses_amount_chk',       $q$amount >= 0$q$),
      ('trip_expenses',   'trip_expenses_liters_chk',       $q$fuel_liters is null or fuel_liters >= 0$q$),
      ('map_posts',       'map_posts_visibility_chk',       $q$visibility in ('private','group','public')$q$),
      ('ai_messages',     'ai_messages_role_chk',           $q$role in ('user','assistant')$q$),
      ('location_pings',  'location_pings_speed_chk',       $q$speed_mps is null or speed_mps >= 0$q$),
      ('location_pings',  'location_pings_heading_chk',     $q$heading is null or (heading >= 0 and heading <= 360)$q$),
      ('trip_stats',      'trip_stats_nonneg_chk',          $q$total_distance_km >= 0 and max_speed_kmh >= 0 and avg_speed_kmh >= 0 and duration_seconds >= 0$q$)
    ) as t(tbl, conname, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.conname) then
      execute format('alter table public.%I add constraint %I check (%s) not valid', c.tbl, c.conname, c.expr);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_trip: reject a group the caller isn't a member of.
-- ---------------------------------------------------------------------------
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
  p_route_polyline text default null
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip public.trips;
begin
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
    created_by, title, group_id, scheduled_start,
    origin_name, origin_point, destination_name, destination_point, route_polyline
  )
  values (
    v_uid, btrim(p_title), p_group_id, p_scheduled_start,
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

  return v_trip;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_trip_route: range-check, and keep existing points when lat/lng are
-- omitted (ST_MakePoint is STRICT, so a NULL coordinate would wipe them).
-- ---------------------------------------------------------------------------
create or replace function public.update_trip_route(
  p_trip uuid,
  p_origin_name text,
  p_origin_lat double precision,
  p_origin_lng double precision,
  p_destination_name text,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_route_polyline text
)
returns public.trips
language plpgsql security definer set search_path = public as $$
declare
  v_trip public.trips;
begin
  if not public.is_trip_participant(p_trip, auth.uid()) then
    raise exception 'not a participant of this trip';
  end if;

  if (p_origin_lat is not null and (p_origin_lat < -90 or p_origin_lat > 90))
     or (p_destination_lat is not null and (p_destination_lat < -90 or p_destination_lat > 90))
     or (p_origin_lng is not null and (p_origin_lng < -180 or p_origin_lng > 180))
     or (p_destination_lng is not null and (p_destination_lng < -180 or p_destination_lng > 180)) then
    raise exception 'coordinates out of range';
  end if;

  update public.trips set
    origin_name = coalesce(p_origin_name, origin_name),
    origin_point = case
      when p_origin_lat is not null and p_origin_lng is not null
      then ST_SetSRID(ST_MakePoint(p_origin_lng, p_origin_lat), 4326)::geography
      else origin_point end,
    destination_name = coalesce(p_destination_name, destination_name),
    destination_point = case
      when p_destination_lat is not null and p_destination_lng is not null
      then ST_SetSRID(ST_MakePoint(p_destination_lng, p_destination_lat), 4326)::geography
      else destination_point end,
    route_polyline = coalesce(p_route_polyline, route_polyline)
  where id = p_trip
  returning * into v_trip;

  return v_trip;
end;
$$;

-- ---------------------------------------------------------------------------
-- reorder_trip_stops: reject NULL elements / duplicates (the previous
-- `id <> all(arr)` guard was NULL-bypassable).
-- ---------------------------------------------------------------------------
create or replace function public.reorder_trip_stops(p_trip uuid, p_stop_ids uuid[])
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_trip_participant(p_trip, auth.uid()) then
    raise exception 'not a participant of this trip';
  end if;

  if p_stop_ids is null or array_position(p_stop_ids, null) is not null then
    raise exception 'p_stop_ids must be a non-null array';
  end if;
  if (select count(*) from unnest(p_stop_ids) as u(id))
     <> (select count(distinct id) from unnest(p_stop_ids) as u(id)) then
    raise exception 'p_stop_ids must not contain duplicates';
  end if;

  if exists (
    select 1 from public.trip_stops
    where trip_id = p_trip and not (id = any (p_stop_ids))
  ) then
    raise exception 'p_stop_ids must include every stop on the trip';
  end if;

  update public.trip_stops s
  set sort_order = ord.idx
  from unnest(p_stop_ids) with ordinality as ord(id, idx)
  where s.id = ord.id and s.trip_id = p_trip;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic scheduler: start every due trip and clear its schedule in one
-- transaction (so a crash can't orphan a schedule that then re-fires).
-- Service-role only.
-- ---------------------------------------------------------------------------
create or replace function public.start_due_scheduled_trips()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select st.id as schedule_id, st.trip_id
    from public.scheduled_trips st
    join public.trips t on t.id = st.trip_id
    where st.scheduled_for <= now() and t.status = 'planned'
    for update of st skip locked
  loop
    update public.trips
    set status = 'active', started_at = now()
    where id = r.trip_id and status = 'planned';
    if found then
      delete from public.scheduled_trips where id = r.schedule_id;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lock down EXECUTE on SECURITY DEFINER helpers/clients from PUBLIC (and thus
-- anon); authenticated keeps access. These are called from RLS policies, so
-- authenticated must retain EXECUTE.
-- ---------------------------------------------------------------------------
revoke execute on function public.is_trip_creator(uuid, uuid) from public;
revoke execute on function public.is_trip_member_any(uuid, uuid) from public;
revoke execute on function public.is_trip_participant(uuid, uuid) from public;
revoke execute on function public.is_group_owner(uuid, uuid) from public;
revoke execute on function public.is_group_member(uuid, uuid) from public;
revoke execute on function public.can_view_map_post(uuid, uuid) from public;
revoke execute on function public.my_private_profile() from public;
revoke execute on function public.trip_member_locations(uuid) from public;
revoke execute on function public.reorder_trip_stops(uuid, uuid[]) from public;
revoke execute on function public.start_due_scheduled_trips() from public, anon, authenticated;

grant execute on function public.is_trip_creator(uuid, uuid) to authenticated;
grant execute on function public.is_trip_member_any(uuid, uuid) to authenticated;
grant execute on function public.is_trip_participant(uuid, uuid) to authenticated;
grant execute on function public.is_group_owner(uuid, uuid) to authenticated;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;
grant execute on function public.can_view_map_post(uuid, uuid) to authenticated;
grant execute on function public.my_private_profile() to authenticated;
grant execute on function public.trip_member_locations(uuid) to authenticated;
grant execute on function public.reorder_trip_stops(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Indexes: FK columns (unindexed by default), the map_posts.storage_path join
-- used by the storage read policy, and GiST on the geography columns.
-- ---------------------------------------------------------------------------
create index if not exists friendships_requester_idx on public.friendships (requester_id);
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);
create index if not exists trips_group_idx on public.trips (group_id);
create index if not exists trips_created_by_idx on public.trips (created_by);
create index if not exists trip_members_user_idx on public.trip_members (user_id);
create index if not exists group_members_user_idx on public.group_members (user_id);
create index if not exists trip_expenses_trip_idx on public.trip_expenses (trip_id);
create index if not exists trip_expenses_user_idx on public.trip_expenses (user_id);
create index if not exists map_posts_trip_idx on public.map_posts (trip_id);
create index if not exists map_posts_user_idx on public.map_posts (user_id);
create index if not exists map_posts_storage_path_idx on public.map_posts (storage_path);
create index if not exists map_post_shares_post_idx on public.map_post_shares (post_id);
create index if not exists chat_messages_sender_idx on public.chat_messages (sender_id);
create index if not exists ai_conversations_user_idx on public.ai_conversations (user_id);
create index if not exists ai_messages_conversation_idx on public.ai_messages (conversation_id);
create index if not exists ai_saved_places_user_idx on public.ai_saved_places (user_id);
create index if not exists scheduled_trips_trip_idx on public.scheduled_trips (trip_id);

create index if not exists trips_origin_gix on public.trips using gist (origin_point);
create index if not exists trips_destination_gix on public.trips using gist (destination_point);
create index if not exists trip_stops_point_gix on public.trip_stops using gist (point);
create index if not exists map_posts_point_gix on public.map_posts using gist (point);
create index if not exists location_pings_point_gix on public.location_pings using gist (point);
