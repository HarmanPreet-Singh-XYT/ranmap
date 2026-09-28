-- ---------------------------------------------------------------------------
-- Ranmap migration 0027: the group as a live convoy — group-scoped presence,
-- and a convoy-alert layer (SOS / regroup / arrival check-ins).
--
-- Until now every live primitive was trip-scoped: the realtime topic
-- `trip-locations:<trip_id>`, `broadcast_position(p_trip,…)`, and the
-- `location_pings.trip_id NOT NULL` snapshot. A group had chat and voice but
-- no idea where its members were, which is exactly what made a group behave
-- like a chat app rather than a convoy.
--
-- This adds the group scope:
--   * `group_locations` — latest known position per member per group (a
--     presence snapshot, not a trail). Written at a coarse cadence so presence
--     survives a cold start without a DB write per GPS fix.
--   * a private realtime channel `group-locations:<group_id>`, authorized by
--     `is_group_member`, and `broadcast_group_position` (server-attested
--     sender, exactly like the trip path).
--   * `group_alerts` — SOS / regroup / arrived / departed signals, plus
--     `alert_checkins` so "who has reached the rendezvous" is real data.
--
-- Live positions still travel as ephemeral broadcasts; only the coarse
-- presence snapshot and the durable alerts touch the database.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Presence snapshot: one row per (group, member), upserted.
-- ---------------------------------------------------------------------------
create table if not exists public.group_locations (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  point geography(point, 4326) not null,
  speed_mps real,
  heading real,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  constraint group_locations_speed_chk check (speed_mps is null or speed_mps >= 0),
  constraint group_locations_heading_chk check (heading is null or (heading >= 0 and heading <= 360))
);

create index if not exists group_locations_updated_idx on public.group_locations (updated_at);

alter table public.group_locations enable row level security;

drop policy if exists "group_locations_select_member" on public.group_locations;
create policy "group_locations_select_member" on public.group_locations
  for select using (public.is_group_member(group_id, auth.uid()));

-- Writes are RPC-only: a client can't write its own (or anyone's) row directly.
revoke insert, update, delete on public.group_locations from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Realtime authorization for the group channel. The trip policy from 0022
-- parsed the id from the topic without checking the channel name, so a
-- `group-locations:` topic could have been authorized as a trip id; both
-- policies now check the topic prefix.
-- ---------------------------------------------------------------------------
drop policy if exists "trip_locations_receive" on realtime.messages;
create policy "trip_locations_receive" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and split_part(realtime.topic(), ':', 1) = 'trip-locations'
    and exists (
      select 1
      from public.trip_members m
      where m.user_id = auth.uid()
        and m.invite_status = 'accepted'
        and m.trip_id::text = split_part(realtime.topic(), ':', 2)
    )
  );

drop policy if exists "group_locations_receive" on realtime.messages;
create policy "group_locations_receive" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and split_part(realtime.topic(), ':', 1) = 'group-locations'
    and public.is_group_member(split_part(realtime.topic(), ':', 2)::uuid, auth.uid())
  );

-- No INSERT policy for either channel: clients never publish directly. Both
-- `broadcast_position` and `broadcast_group_position` emit with a server-set
-- sender id.

-- ---------------------------------------------------------------------------
-- Group presence: broadcast live (ephemeral), persist coarsely (`p_persist`).
-- ---------------------------------------------------------------------------
create or replace function public.broadcast_group_position(
  p_group uuid,
  p_lat double precision,
  p_lng double precision,
  p_speed double precision default null,
  p_heading double precision default null,
  p_persist boolean default false
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_speed real;
  v_heading real;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_group_member(p_group, v_uid) then
    raise exception 'not a member of this group';
  end if;
  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90
     or p_lng < -180 or p_lng > 180 then
    raise exception 'invalid coordinates';
  end if;

  v_speed := case when p_speed >= 0 then p_speed else null end;
  v_heading := case when p_heading >= 0 and p_heading <= 360 then p_heading else null end;

  -- The durable presence snapshot, refreshed at a coarse cadence (the client
  -- only sets p_persist every ~30s). This is what heals a cold start; the
  -- live feed below is ephemeral.
  if p_persist then
    insert into public.group_locations (group_id, user_id, point, speed_mps, heading, updated_at)
    values (
      p_group, v_uid,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      v_speed, v_heading, now()
    )
    on conflict (group_id, user_id) do update set
      point = excluded.point,
      speed_mps = excluded.speed_mps,
      heading = excluded.heading,
      updated_at = excluded.updated_at;
  end if;

  perform realtime.send(
    jsonb_build_object(
      'user_id', v_uid,
      'lat', p_lat,
      'lng', p_lng,
      'speed_mps', v_speed,
      'heading', v_heading,
      'recorded_at', now()
    ),
    'position',
    'group-locations:' || p_group::text,
    true
  );
end;
$$;

-- The current presence snapshot for a group: latest known position per member,
-- dropping entries that went stale (a member who stopped sharing disappears).
create or replace function public.group_member_locations(p_group uuid)
returns table (
  user_id uuid,
  point geography,
  speed_mps real,
  heading real,
  recorded_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select gl.user_id, gl.point, gl.speed_mps, gl.heading, gl.updated_at
  from public.group_locations gl
  where gl.group_id = p_group
    and public.is_group_member(p_group, auth.uid())
    and gl.updated_at > now() - interval '15 minutes';
$$;

-- Retention for stale presence rows. Service-role only (scheduled job).
create or replace function public.prune_group_locations(p_keep_minutes integer default 60)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_deleted integer;
begin
  delete from public.group_locations
  where updated_at < now() - make_interval(mins => greatest(p_keep_minutes, 1));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Convoy alerts: SOS, regroup (a rendezvous point), arrived/departed.
-- ---------------------------------------------------------------------------
create table if not exists public.group_alerts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  message text,
  point geography(point, 4326),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null,
  constraint group_alerts_kind_chk check (kind in ('sos', 'regroup', 'arrived', 'departed')),
  constraint group_alerts_message_len_chk check (message is null or char_length(message) <= 200)
);

create index if not exists group_alerts_group_idx
  on public.group_alerts (group_id, created_at desc);

alter table public.group_alerts enable row level security;

drop policy if exists "group_alerts_select_member" on public.group_alerts;
create policy "group_alerts_select_member" on public.group_alerts
  for select using (public.is_group_member(group_id, auth.uid()));

-- Members raise and resolve alerts through the RPCs below; no direct writes.
revoke insert, update, delete on public.group_alerts from anon, authenticated;

-- Who has reached (or left) a rendezvous point.
create table if not exists public.alert_checkins (
  alert_id uuid not null references public.group_alerts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  arrived_at timestamptz,
  departed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (alert_id, user_id)
);

alter table public.alert_checkins enable row level security;

-- SECURITY DEFINER so the policy can consult group_alerts without the
-- querying user's RLS getting in the way.
create or replace function public.can_view_alert(p_alert uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_alerts a
    where a.id = p_alert and public.is_group_member(a.group_id, p_user)
  );
$$;

drop policy if exists "alert_checkins_select_member" on public.alert_checkins;
create policy "alert_checkins_select_member" on public.alert_checkins
  for select using (public.can_view_alert(alert_id, auth.uid()));

revoke insert, update, delete on public.alert_checkins from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Alert RPCs.
-- ---------------------------------------------------------------------------
create or replace function public.send_group_alert(
  p_group uuid,
  p_kind text,
  p_message text default null,
  p_lat double precision default null,
  p_lng double precision default null
)
returns public.group_alerts
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_alert public.group_alerts;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_group_member(p_group, v_uid) then
    raise exception 'not a member of this group';
  end if;
  if p_kind not in ('sos', 'regroup', 'arrived', 'departed') then
    raise exception 'unknown alert kind';
  end if;
  if p_message is not null and char_length(p_message) > 200 then
    raise exception 'message is too long';
  end if;
  if (p_lat is null) <> (p_lng is null) then
    raise exception 'both coordinates are required together';
  end if;

  insert into public.group_alerts (group_id, created_by, kind, message, point)
  values (
    p_group, v_uid, p_kind, nullif(btrim(coalesce(p_message, '')), ''),
    case when p_lat is not null and p_lng is not null
      then ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography end
  )
  returning * into v_alert;

  return v_alert;
end;
$$;

create or replace function public.resolve_group_alert(p_alert uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_group uuid;
begin
  select group_id into v_group from public.group_alerts where id = p_alert;
  if v_group is null then
    raise exception 'alert not found';
  end if;
  if not public.is_group_admin(v_group, auth.uid()) then
    raise exception 'only an admin can resolve this';
  end if;
  update public.group_alerts
  set resolved_at = now(), resolved_by = auth.uid()
  where id = p_alert and resolved_at is null;
end;
$$;

create or replace function public.check_in_alert(p_alert uuid, p_arrived boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.can_view_alert(p_alert, v_uid) then
    raise exception 'not a member of this group';
  end if;

  insert into public.alert_checkins as ac (alert_id, user_id, arrived_at, departed_at, updated_at)
  values (
    p_alert, v_uid,
    case when p_arrived then now() end,
    case when p_arrived then null else now() end,
    now()
  )
  on conflict (alert_id, user_id) do update set
    arrived_at = case when p_arrived then coalesce(ac.arrived_at, now())
                      else ac.arrived_at end,
    departed_at = case when p_arrived then null else now() end,
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Realtime: alerts and check-ins stream over postgres_changes to members.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['group_alerts', 'alert_checkins']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE grants.
-- ---------------------------------------------------------------------------
revoke execute on function public.broadcast_group_position(uuid, double precision, double precision, double precision, double precision, boolean) from public, anon;
revoke execute on function public.group_member_locations(uuid) from public, anon;
revoke execute on function public.send_group_alert(uuid, text, text, double precision, double precision) from public, anon;
revoke execute on function public.resolve_group_alert(uuid) from public, anon;
revoke execute on function public.check_in_alert(uuid, boolean) from public, anon;
revoke execute on function public.can_view_alert(uuid, uuid) from public, anon;

grant execute on function public.broadcast_group_position(uuid, double precision, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.group_member_locations(uuid) to authenticated;
grant execute on function public.send_group_alert(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function public.resolve_group_alert(uuid) to authenticated;
grant execute on function public.check_in_alert(uuid, boolean) to authenticated;
grant execute on function public.can_view_alert(uuid, uuid) to authenticated;

revoke execute on function public.prune_group_locations(integer) from public, anon, authenticated;
grant execute on function public.prune_group_locations(integer) to service_role;
