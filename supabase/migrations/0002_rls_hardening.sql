-- Ranmap migration 0002: RLS hardening
--
-- Fixes authorization holes found in 0001_init.sql:
--   * any authenticated user could self-join any trip / any group
--   * friendships could be force-accepted on insert and rewritten by the
--     requester (and a decline was a permanent "blocked")
--   * trip-scoped writes (pings, expenses, stats, stops, chat, map posts)
--     were not gated on trip/group membership
--   * profiles exposed every user's phone_number / socials
--   * there were no DELETE policies on any table, so users could never
--     remove their own data, unfriend, or leave a trip/group
--   * no storage.objects policies, so the avatars / map-media buckets were
--     unusable; map_posts.visibility was never consulted
--
-- Safe to re-run (every policy is dropped before it is recreated).

-- ---------------------------------------------------------------------------
-- Helper predicates. SECURITY DEFINER so they bypass RLS themselves, which
-- avoids the recursive-policy trap and keeps the membership rule in one place.
-- ---------------------------------------------------------------------------
create or replace function public.is_trip_creator(p_trip uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.trips t where t.id = p_trip and t.created_by = p_user
  );
$$;

create or replace function public.is_trip_member_any(p_trip uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip and m.user_id = p_user
  );
$$;

-- Creator or an invitee who actually accepted.
create or replace function public.is_trip_participant(p_trip uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_trip_creator(p_trip, p_user)
      or exists (
        select 1 from public.trip_members m
        where m.trip_id = p_trip
          and m.user_id = p_user
          and m.invite_status = 'accepted'
      );
$$;

create or replace function public.is_group_owner(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g where g.id = p_group and g.owner_id = p_user
  );
$$;

create or replace function public.is_group_member(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = p_user
  );
$$;

-- A map post is visible to its owner, when public, when group-scoped and the
-- viewer is on the trip, or when explicitly shared with the viewer / one of
-- their groups.
create or replace function public.can_view_map_post(p_post uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.map_posts p
    where p.id = p_post and (
      p.user_id = p_user
      or p.visibility = 'public'
      or (p.visibility = 'group' and p.trip_id is not null
          and public.is_trip_participant(p.trip_id, p_user))
      or exists (
        select 1 from public.map_post_shares s
        where s.post_id = p.id
          and (
            s.shared_with_user = p_user
            or (s.shared_with_group is not null
                and public.is_group_member(s.shared_with_group, p_user))
          )
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Idempotency: drop every policy on the tables we redefine. This also clears
-- the renamed policies from 0001, so the script can be re-run safely even
-- though several policies below are created under new names.
-- ---------------------------------------------------------------------------
do $$
declare
  pol record;
begin
  for pol in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'profiles', 'friendships', 'groups', 'group_members',
        'trips', 'trip_members', 'trip_stops', 'location_pings',
        'trip_stats', 'trip_expenses', 'map_posts', 'map_post_shares',
        'chat_messages', 'scheduled_trips'
      )
  loop
    execute format('drop policy if exists %I on public.%I', pol.policyname, pol.tablename);
  end loop;

  for pol in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (policyname like 'avatars\_%' or policyname like 'map\_media\_%')
  loop
    execute format('drop policy if exists %I on storage.objects', pol.policyname);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles: keep authenticated read (needed for username search / joins) but
-- stop exposing PII columns to everyone.
-- ---------------------------------------------------------------------------
drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all" on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- phone_number / socials are private: other users can no longer select them.
-- (Insert/update privileges are untouched, so the owner can still write them.)
revoke select on public.profiles from anon, authenticated;
grant select (id, username, display_name, avatar_id, vehicle_type, created_at, updated_at)
  on public.profiles to anon, authenticated;

-- Keep profiles.updated_at honest.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Row-aware escape hatch so a user can still read their own private fields
-- (phone_number / socials) despite the column grants above.
create or replace function public.my_private_profile()
returns table (phone_number text, socials jsonb)
language sql stable security definer set search_path = public as $$
  select p.phone_number, p.socials from public.profiles p where p.id = auth.uid();
$$;

grant execute on function public.my_private_profile() to authenticated;

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------
drop policy if exists "friendships_select_participant" on public.friendships;
create policy "friendships_select_participant" on public.friendships
  for select using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Requests must start pending, from the requester, to someone else.
drop policy if exists "friendships_insert_requester" on public.friendships;
create policy "friendships_insert_requester" on public.friendships
  for insert with check (
    auth.uid() = requester_id
    and status = 'pending'
    and addressee_id <> auth.uid()
  );

-- Only the addressee may accept/block; the requester cancels by deleting.
drop policy if exists "friendships_update_participant" on public.friendships;
create policy "friendships_update_addressee" on public.friendships
  for update using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id);

drop policy if exists "friendships_delete_participant" on public.friendships;
create policy "friendships_delete_participant" on public.friendships
  for delete using (auth.uid() = requester_id or auth.uid() = addressee_id);

revoke update on public.friendships from anon, authenticated;
grant update (status) on public.friendships to anon, authenticated;

-- ---------------------------------------------------------------------------
-- groups & group_members
-- ---------------------------------------------------------------------------
drop policy if exists "groups_select_member" on public.groups;
create policy "groups_select_member" on public.groups
  for select using (
    public.is_group_member(id, auth.uid()) or public.is_group_owner(id, auth.uid())
  );

drop policy if exists "groups_insert_owner" on public.groups;
create policy "groups_insert_owner" on public.groups
  for insert with check (auth.uid() = owner_id);

drop policy if exists "groups_update_owner" on public.groups;
create policy "groups_update_owner" on public.groups
  for update using (public.is_group_owner(id, auth.uid()))
  with check (public.is_group_owner(id, auth.uid()));

drop policy if exists "groups_delete_owner" on public.groups;
create policy "groups_delete_owner" on public.groups
  for delete using (public.is_group_owner(id, auth.uid()));

revoke update on public.groups from anon, authenticated;
grant update (name) on public.groups to anon, authenticated;

drop policy if exists "group_members_select_member" on public.group_members;
create policy "group_members_select_member" on public.group_members
  for select using (public.is_group_member(group_id, auth.uid()));

-- Only the owner may add members (nobody self-joins).
drop policy if exists "group_members_insert_owner_or_self" on public.group_members;
create policy "group_members_insert_owner" on public.group_members
  for insert with check (public.is_group_owner(group_id, auth.uid()));

drop policy if exists "group_members_delete_member_or_owner" on public.group_members;
create policy "group_members_delete_member_or_owner" on public.group_members
  for delete using (
    auth.uid() = user_id or public.is_group_owner(group_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- trips & trip_members
-- ---------------------------------------------------------------------------
-- Any member (incl. a pending invitee) may read the trip row so invite cards
-- can show its title.
drop policy if exists "trips_select_member" on public.trips;
create policy "trips_select_member" on public.trips
  for select using (
    auth.uid() = created_by or public.is_trip_member_any(id, auth.uid())
  );

drop policy if exists "trips_insert_creator" on public.trips;
create policy "trips_insert_creator" on public.trips
  for insert with check (auth.uid() = created_by);

-- Accepted participants can start / complete / edit the trip.
drop policy if exists "trips_update_creator" on public.trips;
create policy "trips_update_participant" on public.trips
  for update using (public.is_trip_participant(id, auth.uid()))
  with check (public.is_trip_participant(id, auth.uid()));

drop policy if exists "trips_delete_creator" on public.trips;
create policy "trips_delete_creator" on public.trips
  for delete using (auth.uid() = created_by);

-- created_by / group_id must not be reassigned.
revoke update on public.trips from anon, authenticated;
grant update (
  title, status, started_at, ended_at,
  origin_name, origin_point, destination_name, destination_point,
  scheduled_start, route_polyline
) on public.trips to anon, authenticated;

drop policy if exists "trip_members_select_member" on public.trip_members;
create policy "trip_members_select_member" on public.trip_members
  for select using (
    auth.uid() = user_id or public.is_trip_participant(trip_id, auth.uid())
  );

-- Only the trip creator may add members (nobody self-joins).
drop policy if exists "trip_members_insert_creator_or_self" on public.trip_members;
create policy "trip_members_insert_creator" on public.trip_members
  for insert with check (public.is_trip_creator(trip_id, auth.uid()));

drop policy if exists "trip_members_update_self" on public.trip_members;
create policy "trip_members_update_self" on public.trip_members
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "trip_members_delete_member_or_creator" on public.trip_members;
create policy "trip_members_delete_member_or_creator" on public.trip_members
  for delete using (
    auth.uid() = user_id or public.is_trip_creator(trip_id, auth.uid())
  );

-- trip_id / user_id must not be reassigned (blocks the "move yourself into
-- another trip" escalation).
revoke update on public.trip_members from anon, authenticated;
grant update (invite_status, joined_at) on public.trip_members to anon, authenticated;

-- ---------------------------------------------------------------------------
-- trip_stops
-- ---------------------------------------------------------------------------
drop policy if exists "trip_stops_select_member" on public.trip_stops;
create policy "trip_stops_select_participant" on public.trip_stops
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_stops_write_member" on public.trip_stops;
create policy "trip_stops_insert_participant" on public.trip_stops
  for insert with check (
    auth.uid() = created_by and public.is_trip_participant(trip_id, auth.uid())
  );

drop policy if exists "trip_stops_update_owner" on public.trip_stops;
create policy "trip_stops_update_owner" on public.trip_stops
  for update using (auth.uid() = created_by) with check (auth.uid() = created_by);

drop policy if exists "trip_stops_delete_owner_or_creator" on public.trip_stops;
create policy "trip_stops_delete_owner_or_creator" on public.trip_stops
  for delete using (
    auth.uid() = created_by or public.is_trip_creator(trip_id, auth.uid())
  );

-- ---------------------------------------------------------------------------
-- location_pings
-- ---------------------------------------------------------------------------
drop policy if exists "location_pings_select_member" on public.location_pings;
create policy "location_pings_select_participant" on public.location_pings
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "location_pings_insert_self" on public.location_pings;
create policy "location_pings_insert_self" on public.location_pings
  for insert with check (
    auth.uid() = user_id and public.is_trip_participant(trip_id, auth.uid())
  );

drop policy if exists "location_pings_delete_self" on public.location_pings;
create policy "location_pings_delete_self" on public.location_pings
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- trip_stats
-- ---------------------------------------------------------------------------
drop policy if exists "trip_stats_select_member" on public.trip_stats;
create policy "trip_stats_select_participant" on public.trip_stats
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_stats_upsert_self" on public.trip_stats;
create policy "trip_stats_insert_self" on public.trip_stats
  for insert with check (
    auth.uid() = user_id and public.is_trip_participant(trip_id, auth.uid())
  );

drop policy if exists "trip_stats_update_self" on public.trip_stats;
create policy "trip_stats_update_self" on public.trip_stats
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id and public.is_trip_participant(trip_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- trip_expenses
-- ---------------------------------------------------------------------------
drop policy if exists "trip_expenses_select_member" on public.trip_expenses;
create policy "trip_expenses_select_participant" on public.trip_expenses
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "trip_expenses_insert_self" on public.trip_expenses;
create policy "trip_expenses_insert_self" on public.trip_expenses
  for insert with check (
    auth.uid() = user_id and public.is_trip_participant(trip_id, auth.uid())
  );

drop policy if exists "trip_expenses_delete_self" on public.trip_expenses;
create policy "trip_expenses_delete_self" on public.trip_expenses
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- map_posts & map_post_shares
-- ---------------------------------------------------------------------------
drop policy if exists "map_posts_select_owner_or_shared" on public.map_posts;
create policy "map_posts_select_visible" on public.map_posts
  for select using (public.can_view_map_post(id, auth.uid()));

drop policy if exists "map_posts_insert_self" on public.map_posts;
create policy "map_posts_insert_self" on public.map_posts
  for insert with check (
    auth.uid() = user_id
    and (trip_id is null or public.is_trip_participant(trip_id, auth.uid()))
  );

drop policy if exists "map_posts_update_owner" on public.map_posts;
create policy "map_posts_update_owner" on public.map_posts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "map_posts_delete_owner" on public.map_posts;
create policy "map_posts_delete_owner" on public.map_posts
  for delete using (auth.uid() = user_id);

drop policy if exists "map_post_shares_select_related" on public.map_post_shares;
create policy "map_post_shares_select_related" on public.map_post_shares
  for select using (
    shared_with_user = auth.uid()
    or (shared_with_group is not null
        and public.is_group_member(shared_with_group, auth.uid()))
    or exists (select 1 from public.map_posts p where p.id = post_id and p.user_id = auth.uid())
  );

drop policy if exists "map_post_shares_insert_post_owner" on public.map_post_shares;
create policy "map_post_shares_insert_post_owner" on public.map_post_shares
  for insert with check (
    exists (select 1 from public.map_posts p where p.id = post_id and p.user_id = auth.uid())
  );

drop policy if exists "map_post_shares_delete_post_owner" on public.map_post_shares;
create policy "map_post_shares_delete_post_owner" on public.map_post_shares
  for delete using (
    exists (select 1 from public.map_posts p where p.id = post_id and p.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- chat_messages
-- ---------------------------------------------------------------------------
drop policy if exists "chat_messages_select_member" on public.chat_messages;
create policy "chat_messages_select_member" on public.chat_messages
  for select using (
    (trip_id is not null and public.is_trip_participant(trip_id, auth.uid()))
    or (group_id is not null and public.is_group_member(group_id, auth.uid()))
  );

drop policy if exists "chat_messages_insert_sender" on public.chat_messages;
create policy "chat_messages_insert_sender" on public.chat_messages
  for insert with check (
    auth.uid() = sender_id
    and (
      (trip_id is not null and public.is_trip_participant(trip_id, auth.uid()))
      or (group_id is not null and public.is_group_member(group_id, auth.uid()))
    )
  );

drop policy if exists "chat_messages_delete_sender" on public.chat_messages;
create policy "chat_messages_delete_sender" on public.chat_messages
  for delete using (auth.uid() = sender_id);

-- ---------------------------------------------------------------------------
-- scheduled_trips
-- ---------------------------------------------------------------------------
drop policy if exists "scheduled_trips_select_member" on public.scheduled_trips;
create policy "scheduled_trips_select_participant" on public.scheduled_trips
  for select using (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "scheduled_trips_insert_member" on public.scheduled_trips;
create policy "scheduled_trips_insert_participant" on public.scheduled_trips
  for insert with check (public.is_trip_participant(trip_id, auth.uid()));

drop policy if exists "scheduled_trips_delete_creator" on public.scheduled_trips;
create policy "scheduled_trips_delete_creator" on public.scheduled_trips
  for delete using (public.is_trip_creator(trip_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- Storage policies (buckets were created in 0001 with none).
-- Convention: objects live under a "<auth.uid()>/..." prefix.
-- ---------------------------------------------------------------------------
drop policy if exists "avatars_read_all" on storage.objects;
create policy "avatars_read_all" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "map_media_insert_own" on storage.objects;
create policy "map_media_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'map-media' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "map_media_update_own" on storage.objects;
create policy "map_media_update_own" on storage.objects
  for update using (
    bucket_id = 'map-media' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "map_media_delete_own" on storage.objects;
create policy "map_media_delete_own" on storage.objects
  for delete using (
    bucket_id = 'map-media' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Private bucket: readable only by the owner or viewers of the post that
-- references the object.
drop policy if exists "map_media_read_visible" on storage.objects;
create policy "map_media_read_visible" on storage.objects
  for select using (
    bucket_id = 'map-media'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.map_posts p
        where p.storage_path = storage.objects.name
          and public.can_view_map_post(p.id, auth.uid())
      )
    )
  );
