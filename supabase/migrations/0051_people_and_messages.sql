-- ---------------------------------------------------------------------------
-- Ranmap migration 0051: people you know, and messaging beyond friends.
--
-- Three related gaps, all around "who can I reach, and how":
--
--   1. There was no single answer to "who do I know?". Relationship data lived
--      in four places (friendships, trip_members, group_members, and the DM
--      table), each readable only one scope at a time. `people_around_me()`
--      flattens them into one ranked list for the People screen — friend first,
--      then whoever you're riding with right now, then people from past trips,
--      then people you share a group with — with the caller's own view of
--      whether each person may be messaged.
--
--   2. Direct messages were friend-only, enforced inside
--      `get_or_create_conversation`. `profiles.dm_from_strangers` makes that a
--      per-person choice (off by default, so nothing changes unless you opt in),
--      and a message thread that a stranger legitimately started stays usable by
--      both sides — blocking is still the way to close one.
--
--   3. Adding a friend to a group silently made them a member. Trips already
--      model this properly (`invite_status` + an accept step); groups now have
--      the same shape: an admin *invites*, and the invitee accepts or declines.
--      Invites sit as `pending` rows, so they don't consume the free member cap
--      until someone accepts.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 1. May someone who isn't a friend start a DM with me? Off by default.
-- ---------------------------------------------------------------------------
alter table public.profiles
add column if not exists dm_from_strangers boolean not null default false;
-- Column-level, like every other client-writable profile field (see 0009).
revoke
update on public.profiles
from anon,
  authenticated;
grant update (
    username,
    display_name,
    avatar_id,
    vehicle_type,
    phone_number,
    socials,
    dm_from_strangers
  ) on public.profiles to anon,
  authenticated;
-- The owner's own view of their private fields. `dm_from_strangers` is a
-- preference rather than a profile detail, so it isn't in the public
-- select-column grant — it is surfaced here, to its owner only.
-- `create or replace` can't change OUT columns, so drop the old shape first.
drop function if exists public.my_private_profile();
create or replace function public.my_private_profile() returns table (
    phone_number text,
    socials jsonb,
    phone_verified boolean,
    dm_from_strangers boolean
  ) language sql stable security definer
set search_path = public as $$
select p.phone_number,
  p.socials,
  p.phone_verified,
  p.dm_from_strangers
from public.profiles p
where p.id = auth.uid();
$$;
revoke execute on function public.my_private_profile()
from public,
  anon;
grant execute on function public.my_private_profile() to authenticated,
  service_role;
-- ---------------------------------------------------------------------------
-- 2. The People screen's single query.
-- ---------------------------------------------------------------------------
create or replace function public.people_around_me() returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_id text,
    vehicle_type text,
    relationship text,
    is_friend boolean,
    can_message boolean
  ) language sql stable security definer
set search_path = public as $$ with me as (
    select auth.uid() as uid
  ),
  -- Every reason this person is in my orbit, with the strongest one winning
  -- below: friend (3) > riding with me now (2) > been on a trip together (1) >
  -- both in a group (0).
  reasons as (
    select case
        when f.requester_id = me.uid then f.addressee_id
        else f.requester_id
      end as person,
      'friend'::text as rel,
      3 as weight
    from public.friendships f
      cross join me
    where f.status = 'accepted'
      and me.uid in (f.requester_id, f.addressee_id)
    union all
    -- Crew on a trip that is running right now.
    select other.user_id,
      'riding',
      2
    from public.trip_members mine
      cross join me
      join public.trips t on t.id = mine.trip_id
      and t.status = 'active'
      join public.trip_members other on other.trip_id = mine.trip_id
      and other.user_id <> me.uid
      and other.invite_status = 'accepted'
    where mine.user_id = me.uid
      and mine.invite_status = 'accepted'
    union all
    -- People from trips that are not running: past meets.
    select other.user_id,
      'travelled',
      1
    from public.trip_members mine
      cross join me
      join public.trips t on t.id = mine.trip_id
      and t.status <> 'active'
      join public.trip_members other on other.trip_id = mine.trip_id
      and other.user_id <> me.uid
      and other.invite_status = 'accepted'
    where mine.user_id = me.uid
      and mine.invite_status = 'accepted'
    union all
    -- People in a group we are both active in.
    select other.user_id,
      'group',
      0
    from public.group_members mine
      cross join me
      join public.group_members other on other.group_id = mine.group_id
      and other.user_id <> me.uid
      and other.status = 'active'
    where mine.user_id = me.uid
      and mine.status = 'active'
  ),
  best as (
    select distinct on (r.person) r.person as person,
      r.rel as rel
    from reasons r
    order by r.person,
      r.weight desc
  )
select b.person,
  p.username,
  p.display_name,
  p.avatar_id,
  p.vehicle_type,
  b.rel,
  public.are_friends(me.uid, b.person),
  (
    public.are_friends(me.uid, b.person)
    or coalesce(p.dm_from_strangers, false)
  )
  and not public.is_blocked_between(me.uid, b.person)
from best b
  cross join me
  join public.profiles p on p.id = b.person -- A block hides the person everywhere, not just in chat.
where not public.is_blocked_between(me.uid, b.person)
order by (b.rel = 'friend') desc,
  (b.rel = 'riding') desc,
  p.username;
$$;
revoke execute on function public.people_around_me()
from public,
  anon;
grant execute on function public.people_around_me() to authenticated,
  service_role;
-- ---------------------------------------------------------------------------
-- 3. A stranger thread is allowed when the recipient says so, and once it
--    exists both sides can use it. Blocking still wins.
-- ---------------------------------------------------------------------------
create or replace function public.get_or_create_conversation(p_other uuid) returns uuid language plpgsql security definer
set search_path = public as $$
declare v_uid uuid := auth.uid();
v_a uuid;
v_b uuid;
v_id uuid;
begin if v_uid is null then raise exception 'not authenticated';
end if;
if p_other is null
or p_other = v_uid then raise exception 'invalid recipient';
end if;
-- Friends always; otherwise the recipient has to have opted in to messages
-- from people they don't know. This is the *only* gate — posting inside an
-- existing thread is handled by can_post_in_conversation below.
if not public.are_friends(v_uid, p_other)
and not coalesce(
  (
    select p.dm_from_strangers
    from public.profiles p
    where p.id = p_other
  ),
  false
) then raise exception 'This person only accepts messages from friends.' using errcode = '42501';
end if;
if public.is_blocked_between(v_uid, p_other) then raise exception 'You cannot message this person.' using errcode = '42501';
end if;
v_a := least(v_uid, p_other);
v_b := greatest(v_uid, p_other);
select c.id into v_id
from public.direct_conversations c
where c.user_a = v_a
  and c.user_b = v_b;
if v_id is null then
insert into public.direct_conversations (user_a, user_b)
values (v_a, v_b)
returning id into v_id;
end if;
return v_id;
end;
$$;
-- Posting: membership + no block + (still friends, or either side allows
-- strangers). Without the last clause an accepted stranger thread would be
-- readable but unusable.
create or replace function public.can_post_in_conversation(p_conv uuid, p_user uuid) returns boolean language sql stable security definer
set search_path = public as $$
select exists (
    select 1
    from public.direct_conversations c
    where c.id = p_conv
      and p_user in (c.user_a, c.user_b)
      and not public.is_blocked_between(c.user_a, c.user_b)
      and (
        public.are_friends(c.user_a, c.user_b)
        or coalesce(
          (
            select p.dm_from_strangers
            from public.profiles p
            where p.id = c.user_a
          ),
          false
        )
        or coalesce(
          (
            select p.dm_from_strangers
            from public.profiles p
            where p.id = c.user_b
          ),
          false
        )
      )
  );
$$;
-- ---------------------------------------------------------------------------
-- 4. Group invites: an admin invites a friend, the friend accepts.
-- ---------------------------------------------------------------------------
alter table public.group_members
add column if not exists invited_by uuid references public.profiles (id) on delete
set null;
create index if not exists group_members_invited_by_idx on public.group_members (invited_by)
where invited_by is not null;
-- The invite lands as a pending row, so it costs nothing against the free
-- member cap until the invitee accepts (see enforce_group_member_limit).
create or replace function public.invite_group_member(p_group uuid, p_user uuid) returns void language plpgsql security definer
set search_path = public as $$
declare v_uid uuid := auth.uid();
begin if v_uid is null then raise exception 'not authenticated';
end if;
if not public.is_group_admin(p_group, v_uid) then raise exception 'Only a group admin can invite members.' using errcode = '42501';
end if;
if p_user is null
or p_user = v_uid then raise exception 'invalid invitee';
end if;
-- Friends only: a group must not become a way to cold-call strangers.
if not public.are_friends(v_uid, p_user) then raise exception 'You can only invite friends.' using errcode = '42501';
end if;
-- Already a member, already invited, or already asked to join: nothing to do.
if exists (
  select 1
  from public.group_members m
  where m.group_id = p_group
    and m.user_id = p_user
) then return;
end if;
insert into public.group_members (group_id, user_id, role, status, invited_by)
values (p_group, p_user, 'member', 'pending', v_uid);
end;
$$;
revoke execute on function public.invite_group_member(uuid, uuid)
from public,
  anon;
grant execute on function public.invite_group_member(uuid, uuid) to authenticated,
  service_role;
-- The invitee's side: what have I been invited to?
create or replace function public.my_group_invites() returns table (
    group_id uuid,
    name text,
    invited_by uuid,
    inviter_username text
  ) language sql stable security definer
set search_path = public as $$
select g.id,
  g.name,
  m.invited_by,
  p.username
from public.group_members m
  join public.groups g on g.id = m.group_id
  left join public.profiles p on p.id = m.invited_by
where m.user_id = auth.uid()
  and m.status = 'pending'
  and m.invited_by is not null
order by g.name;
$$;
revoke execute on function public.my_group_invites()
from public,
  anon;
grant execute on function public.my_group_invites() to authenticated,
  service_role;
-- Accept (activate) or decline (drop the row). Only the invitee can act, and
-- only on a row they were actually invited to — a pending *join request* is the
-- admin's to resolve (respond_group_request).
create or replace function public.respond_group_invite(p_group uuid, p_accept boolean) returns void language plpgsql security definer
set search_path = public as $$
declare v_uid uuid := auth.uid();
begin if v_uid is null then raise exception 'not authenticated';
end if;
if p_accept then
update public.group_members
set status = 'active',
  joined_at = now()
where group_id = p_group
  and user_id = v_uid
  and status = 'pending'
  and invited_by is not null;
else
delete from public.group_members
where group_id = p_group
  and user_id = v_uid
  and status = 'pending'
  and invited_by is not null;
end if;
end;
$$;
revoke execute on function public.respond_group_invite(uuid, boolean)
from public,
  anon;
grant execute on function public.respond_group_invite(uuid, boolean) to authenticated,
  service_role;