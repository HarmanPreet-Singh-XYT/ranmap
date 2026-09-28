-- ---------------------------------------------------------------------------
-- Ranmap migration 0026: real group membership — admins, ownership transfer,
-- invite links / join codes, join requests & approval, and group editing.
--
-- Before this, `group_members.role` existed but was decorative: only 'owner'
-- and 'member' were ever written, nothing read the column for authorization
-- (every policy keyed off `groups.owner_id`), there was no UPDATE policy so a
-- role could never change, an owner could never leave (their only exit was
-- deleting the group), and the only way in was an owner manually adding a
-- pre-existing friend — no invite links, no join requests, no approval.
--
-- This migration makes the role column authoritative and adds the WhatsApp-
-- style flows:
--   * owner / admin / member, enforced in RLS and via RPCs
--   * promote / demote
--   * ownership transfer, and an owner can finally leave
--   * a revocable invite code per group (+ optional join approval)
--   * pending membership, approvable/deniable by an admin
--   * group name / description / avatar editing
--
-- All role changes go through SECURITY DEFINER RPCs: no client ever has a
-- column-level UPDATE grant on `group_members.role`/`status`, so a patched
-- client can't promote itself.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- New columns.
-- ---------------------------------------------------------------------------
alter table public.groups
  add column if not exists description text,
  add column if not exists avatar_id text not null default 'default',
  add column if not exists invite_code text,
  add column if not exists invite_requires_approval boolean not null default false;

-- Active vs pending membership. Existing rows are all active.
alter table public.group_members
  add column if not exists status text not null default 'active';

-- Text / enum backstops (mirror 0007 / 0012). NOT VALID so pre-existing rows
-- can't block the migration; new writes are still enforced.
do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('group_members', 'group_members_status_chk',  $q$status in ('pending','active')$q$),
      ('groups',        'groups_description_len_chk', $q$description is null or char_length(description) <= 200$q$),
      ('groups',        'groups_avatar_len_chk',     $q$char_length(avatar_id) between 1 and 64$q$),
      ('groups',        'groups_invite_code_len_chk', $q$invite_code is null or char_length(invite_code) between 6 and 32$q$)
    ) as t(tbl, conname, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.conname) then
      execute format('alter table public.%I add constraint %I check (%s) not valid', c.tbl, c.conname, c.expr);
    end if;
  end loop;
end;
$$;

-- One invite code per group, and unique across groups.
create unique index if not exists groups_invite_code_key
  on public.groups (invite_code);
create index if not exists group_members_status_idx
  on public.group_members (group_id, status);

-- ---------------------------------------------------------------------------
-- Invite-code generator: 12 lowercase hex chars (48 bits) — no ambiguous
-- characters, and short enough to type by hand.
-- ---------------------------------------------------------------------------
create or replace function public.random_invite_code()
returns text language sql volatile set search_path = public as $$
  select substr(
    md5(gen_random_uuid()::text || clock_timestamp()::text || random()::text),
    1, 12
  );
$$;

revoke execute on function public.random_invite_code() from public, anon, authenticated;

-- Backfill existing groups so every group has a working code.
update public.groups set invite_code = public.random_invite_code() where invite_code is null;

-- ---------------------------------------------------------------------------
-- Helper predicates. `is_group_member` now means an *active* member — a
-- pending requester must not reach the group's channels, map shares or voice.
-- ---------------------------------------------------------------------------
create or replace function public.is_group_member(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group
      and m.user_id = p_user
      and m.status = 'active'
  );
$$;

-- Owner or an active admin.
create or replace function public.is_group_admin(p_group uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_group_owner(p_group, p_user)
      or exists (
        select 1 from public.group_members m
        where m.group_id = p_group
          and m.user_id = p_user
          and m.status = 'active'
          and m.role in ('owner', 'admin')
      );
$$;

revoke execute on function public.is_group_admin(uuid, uuid) from public, anon;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;

-- Keep "travel together" entitlement to members who actually joined.
create or replace function public.group_has_pro(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group and public.is_pro(g.owner_id)
  ) or exists (
    select 1 from public.group_members m
    where m.group_id = p_group
      and m.status = 'active'
      and public.is_pro(m.user_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- Policies. Recreate the group ones to key off membership role.
-- ---------------------------------------------------------------------------
drop policy if exists "groups_select_member" on public.groups;
create policy "groups_select_member" on public.groups
  for select using (
    public.is_group_member(id, auth.uid()) or public.is_group_admin(id, auth.uid())
  );

drop policy if exists "groups_update_owner" on public.groups;
create policy "groups_update_admin" on public.groups
  for update using (public.is_group_admin(id, auth.uid()))
  with check (public.is_group_admin(id, auth.uid()));

-- A group is edited only through update_group(), so take the direct UPDATE
-- grant away (it currently exposes `name` to owners, bypassing validation).
revoke update on public.groups from anon, authenticated;

drop policy if exists "group_members_select_member" on public.group_members;
create policy "group_members_select_member" on public.group_members
  for select using (
    -- Active members are visible to any active member.
    (status = 'active' and public.is_group_member(group_id, auth.uid()))
    -- Admins see everything, including pending join requests.
    or public.is_group_admin(group_id, auth.uid())
    -- You can always see your own row (e.g. a pending request you made).
    or user_id = auth.uid()
  );

-- Admins add members directly (the "add a friend" path); everyone else joins
-- through join_group().
drop policy if exists "group_members_insert_owner" on public.group_members;
create policy "group_members_insert_admin" on public.group_members
  for insert with check (public.is_group_admin(group_id, auth.uid()));

-- A member may remove themselves (unless they own the group — an owner leaves
-- via leave_group(), which transfers or deletes); an admin may remove anyone
-- except the owner.
drop policy if exists "group_members_delete_member_or_owner" on public.group_members;
create policy "group_members_delete_admin_or_self" on public.group_members
  for delete using (
    (auth.uid() = user_id and not public.is_group_owner(group_id, auth.uid()))
    or public.is_group_owner(group_id, auth.uid())
    or (public.is_group_admin(group_id, auth.uid()) and not public.is_group_owner(group_id, user_id))
  );

-- Role/status changes are RPC-only: no UPDATE grant, so a client can't promote
-- itself even with a crafted request.
revoke update on public.group_members from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Free-tier member cap now counts active members only, and also fires when a
-- pending request is approved (status flips to active).
-- ---------------------------------------------------------------------------
create or replace function public.enforce_group_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' then
    return new;
  end if;
  if public.is_pro(new.user_id) or public.group_has_pro(new.group_id) then
    return new;
  end if;
  if (select count(*) from public.group_members m
      where m.group_id = new.group_id and m.status = 'active')
      >= public.plan_limit('group_members') then
    raise exception 'Ranmap Pro required: free groups are limited to % members.',
      public.plan_limit('group_members') using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists group_members_free_limit on public.group_members;
create trigger group_members_free_limit
  before insert or update of status on public.group_members
  for each row execute function public.enforce_group_member_limit();

-- ---------------------------------------------------------------------------
-- create_group: also mint an invite code and a random group avatar.
-- (Signature unchanged, so the client call site still works.)
-- ---------------------------------------------------------------------------
create or replace function public.create_group(p_name text)
returns public.groups
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;

  insert into public.groups (name, owner_id, avatar_id, invite_code)
  values (
    btrim(p_name),
    v_uid,
    -- A 12-hex-char identicon seed. md5() rather than gen_random_bytes() so the
    -- function doesn't depend on pgcrypto being on this function's search_path.
    substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 12),
    public.random_invite_code()
  )
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role, status)
  values (v_group.id, v_uid, 'owner', 'active');

  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_group: rename / re-describe / re-avatar. Admin only.
-- ---------------------------------------------------------------------------
create or replace function public.update_group(
  p_group uuid,
  p_name text,
  p_description text default null,
  p_avatar_id text default null
)
returns public.groups
language plpgsql security definer set search_path = public as $$
declare
  v_group public.groups;
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can edit this group';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;
  if char_length(btrim(p_name)) > 60 then
    raise exception 'name is too long';
  end if;
  if p_description is not null and char_length(p_description) > 200 then
    raise exception 'description is too long';
  end if;
  if p_avatar_id is not null
     and (char_length(p_avatar_id) < 1 or char_length(p_avatar_id) > 64) then
    raise exception 'invalid avatar';
  end if;

  update public.groups set
    name = btrim(p_name),
    description = p_description,
    avatar_id = coalesce(p_avatar_id, avatar_id)
  where id = p_group
  returning * into v_group;

  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- Invite code management. Admin only.
-- ---------------------------------------------------------------------------
create or replace function public.rotate_group_invite_code(p_group uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can change the invite link';
  end if;
  v_code := public.random_invite_code();
  update public.groups set invite_code = v_code where id = p_group;
  return v_code;
end;
$$;

create or replace function public.set_group_invite_approval(
  p_group uuid,
  p_requires boolean
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can change this setting';
  end if;
  update public.groups set invite_requires_approval = p_requires where id = p_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- join_group: redeem an invite code.
-- Returns {status, group_id} where status is one of:
--   joined | already_member | pending | already_requested | not_found
-- ---------------------------------------------------------------------------
create or replace function public.join_group(p_code text)
returns table (status text, group_id uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
  v_existing public.group_members;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_group
  from public.groups g
  where g.invite_code = lower(btrim(p_code));

  if not found then
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  select * into v_existing
  from public.group_members m
  where m.group_id = v_group.id and m.user_id = v_uid;

  if found then
    if v_existing.status = 'active' then
      return query select 'already_member'::text, v_group.id;
    else
      return query select 'already_requested'::text, v_group.id;
    end if;
    return;
  end if;

  if v_group.invite_requires_approval then
    insert into public.group_members (group_id, user_id, role, status)
    values (v_group.id, v_uid, 'member', 'pending');
    return query select 'pending'::text, v_group.id;
  else
    insert into public.group_members (group_id, user_id, role, status)
    values (v_group.id, v_uid, 'member', 'active');
    return query select 'joined'::text, v_group.id;
  end if;
end;
$$;

-- Preview an invite without joining (the group isn't readable to a non-member).
create or replace function public.group_invite_preview(p_code text)
returns table (
  group_id uuid,
  name text,
  description text,
  avatar_id text,
  member_count int,
  requires_approval boolean,
  membership text
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
  v_status text;
begin
  select * into v_group
  from public.groups g
  where g.invite_code = lower(btrim(p_code));

  if not found then
    return;
  end if;

  select m.status into v_status
  from public.group_members m
  where m.group_id = v_group.id and m.user_id = v_uid;

  return query select
    v_group.id,
    v_group.name,
    v_group.description,
    v_group.avatar_id,
    (select count(*)::int from public.group_members m
      where m.group_id = v_group.id and m.status = 'active'),
    v_group.invite_requires_approval,
    coalesce(
      case when v_status = 'active' then 'member'
           when v_status = 'pending' then 'pending'
           else null end,
      'none'
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- respond_group_request: an admin approves (active) or denies (row removed).
-- ---------------------------------------------------------------------------
create or replace function public.respond_group_request(
  p_group uuid,
  p_user uuid,
  p_accept boolean
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can answer join requests';
  end if;
  if public.is_group_owner(p_group, p_user) then
    raise exception 'cannot answer the owner';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = p_user and m.status = 'pending'
  ) then
    raise exception 'no pending request from that user';
  end if;

  if p_accept then
    update public.group_members
    set status = 'active'
    where group_id = p_group and user_id = p_user;
  else
    delete from public.group_members
    where group_id = p_group and user_id = p_user;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- set_group_member_role: promote / demote. Admin only; never the owner.
-- ---------------------------------------------------------------------------
create or replace function public.set_group_member_role(
  p_group uuid,
  p_user uuid,
  p_role text
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can change roles';
  end if;
  if p_role not in ('admin', 'member') then
    raise exception 'role must be admin or member';
  end if;
  if public.is_group_owner(p_group, p_user) then
    raise exception 'cannot change the owner''s role';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = p_user and m.status = 'active'
  ) then
    raise exception 'that user is not an active member';
  end if;

  update public.group_members
  set role = p_role
  where group_id = p_group and user_id = p_user;
end;
$$;

-- ---------------------------------------------------------------------------
-- transfer_group_ownership: hand the crown over, then the old owner can leave.
-- ---------------------------------------------------------------------------
create or replace function public.transfer_group_ownership(
  p_group uuid,
  p_new_owner uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.is_group_owner(p_group, v_uid) then
    raise exception 'only the owner can transfer ownership';
  end if;
  if p_new_owner = v_uid then
    raise exception 'you already own this group';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = p_new_owner and m.status = 'active'
  ) then
    raise exception 'the new owner must be an active member';
  end if;

  update public.groups set owner_id = p_new_owner where id = p_group;
  update public.group_members set role = 'owner'
    where group_id = p_group and user_id = p_new_owner;
  update public.group_members set role = 'admin'
    where group_id = p_group and user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- leave_group: a member removes themselves. An owner must transfer first
-- (unless they're the last one, in which case the group is deleted).
-- ---------------------------------------------------------------------------
create or replace function public.leave_group(p_group uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_others int;
begin
  if not public.is_group_member(p_group, v_uid) then
    raise exception 'you are not a member of this group';
  end if;

  if public.is_group_owner(p_group, v_uid) then
    select count(*) into v_others
    from public.group_members m
    where m.group_id = p_group and m.status = 'active' and m.user_id <> v_uid;

    if v_others > 0 then
      raise exception 'transfer ownership before leaving';
    end if;
    delete from public.groups where id = p_group;
    return;
  end if;

  delete from public.group_members
  where group_id = p_group and user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- EXECUTE grants: authenticated only, never anon/PUBLIC.
-- ---------------------------------------------------------------------------
revoke execute on function public.update_group(uuid, text, text, text) from public, anon;
revoke execute on function public.rotate_group_invite_code(uuid) from public, anon;
revoke execute on function public.set_group_invite_approval(uuid, boolean) from public, anon;
revoke execute on function public.join_group(text) from public, anon;
revoke execute on function public.group_invite_preview(text) from public, anon;
revoke execute on function public.respond_group_request(uuid, uuid, boolean) from public, anon;
revoke execute on function public.set_group_member_role(uuid, uuid, text) from public, anon;
revoke execute on function public.transfer_group_ownership(uuid, uuid) from public, anon;
revoke execute on function public.leave_group(uuid) from public, anon;

grant execute on function public.update_group(uuid, text, text, text) to authenticated;
grant execute on function public.rotate_group_invite_code(uuid) to authenticated;
grant execute on function public.set_group_invite_approval(uuid, boolean) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.group_invite_preview(text) to authenticated;
grant execute on function public.respond_group_request(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_group_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Notification preference for group activity (invites, requests, approvals).
-- ---------------------------------------------------------------------------
alter table public.notification_prefs
  add column if not exists group_invites boolean not null default true;
