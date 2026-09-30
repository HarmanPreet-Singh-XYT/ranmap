-- 0046_moderation.sql
--
-- User safety controls required by the App Store (Guideline 1.2, User-Generated
-- Content) and Google Play's UGC policy: the ability to BLOCK an abusive user
-- and to REPORT objectionable content, with the block enforced server-side (not
-- just hidden in the client).
--
-- What this adds:
--   * user_blocks   — a directional block (blocker → blocked). Blocking also
--     deletes any friendship/request between the pair, which closes their direct
--     message thread (can_post_in_conversation requires friendship).
--   * content_reports — an append-only report queue (users, messages, posts,
--     groups). Users write and read back only their own; staff read the whole
--     queue with the service role.
--   * enforcement: friendships can no longer be created across a block,
--     can_post_in_conversation refuses while a block exists, and search_profiles
--     hides blocked users in both directions.
--
-- Blocking is between two people. Multi-party trip/group chats are not split per
-- member (an admin removes a member instead); the block stops the one-to-one
-- channels and the friend relationship.
--
-- Additive and safe to re-run: tables/policies are guarded, functions are
-- `create or replace`.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self_chk check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_id);

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null,
  target_id uuid not null,
  reason text not null,
  details text,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  constraint content_reports_target_type_chk
    check (target_type in ('user', 'message', 'post', 'group')),
  constraint content_reports_reason_chk
    check (reason in ('spam', 'harassment', 'explicit', 'violence', 'other')),
  constraint content_reports_status_chk
    check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  constraint content_reports_details_len_chk
    check (details is null or char_length(details) <= 1000)
);

create index if not exists content_reports_reporter_idx
  on public.content_reports (reporter_id);
create index if not exists content_reports_status_idx
  on public.content_reports (status, created_at);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.user_blocks enable row level security;
alter table public.content_reports enable row level security;

-- You manage your own blocks; you can see a block you made or that names you
-- (so the client can hide the other party).
drop policy if exists "user_blocks_select_involved" on public.user_blocks;
create policy "user_blocks_select_involved" on public.user_blocks
  for select using (auth.uid() in (blocker_id, blocked_id));

drop policy if exists "user_blocks_insert_blocker" on public.user_blocks;
create policy "user_blocks_insert_blocker" on public.user_blocks
  for insert with check (auth.uid() = blocker_id and blocker_id <> blocked_id);

drop policy if exists "user_blocks_delete_blocker" on public.user_blocks;
create policy "user_blocks_delete_blocker" on public.user_blocks
  for delete using (auth.uid() = blocker_id);

-- Reports are append-only for the reporter; staff read the queue via the
-- service role (which bypasses RLS).
drop policy if exists "content_reports_insert_reporter" on public.content_reports;
create policy "content_reports_insert_reporter" on public.content_reports
  for insert with check (auth.uid() = reporter_id);

drop policy if exists "content_reports_select_reporter" on public.content_reports;
create policy "content_reports_select_reporter" on public.content_reports
  for select using (auth.uid() = reporter_id);

revoke all on public.user_blocks from anon, authenticated;
grant select, insert, delete on public.user_blocks to authenticated;
revoke all on public.content_reports from anon, authenticated;
grant select, insert on public.content_reports to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- True when either side has blocked the other. SECURITY DEFINER so RLS policies
-- can consult user_blocks without depending on the caller's own visibility.
create or replace function public.is_blocked_between(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_a and b.blocked_id = p_b)
       or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

revoke execute on function public.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function public.is_blocked_between(uuid, uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------
create or replace function public.block_user(p_target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_target is null or p_target = v_uid then
    raise exception 'invalid target';
  end if;

  insert into public.user_blocks (blocker_id, blocked_id)
  values (v_uid, p_target)
  on conflict do nothing;

  -- Blocking severs the friendship (and any pending request), which also closes
  -- the direct-message thread via can_post_in_conversation.
  delete from public.friendships f
  where (f.requester_id = v_uid and f.addressee_id = p_target)
     or (f.requester_id = p_target and f.addressee_id = v_uid);
end;
$$;

revoke execute on function public.block_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(p_target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  delete from public.user_blocks
  where blocker_id = v_uid and blocked_id = p_target;
end;
$$;

revoke execute on function public.unblock_user(uuid) from public, anon;
grant execute on function public.unblock_user(uuid) to authenticated;

create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_target_type not in ('user', 'message', 'post', 'group') then
    raise exception 'invalid target type';
  end if;
  if p_reason not in ('spam', 'harassment', 'explicit', 'violence', 'other') then
    raise exception 'invalid reason';
  end if;
  if p_target_id is null then raise exception 'invalid target'; end if;

  insert into public.content_reports (reporter_id, target_type, target_id, reason, details)
  values (
    v_uid,
    p_target_type,
    p_target_id,
    p_reason,
    nullif(btrim(coalesce(p_details, '')), '')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Enforcement
-- ---------------------------------------------------------------------------

-- A friend request can't cross a block in either direction.
drop policy if exists "friendships_insert_requester" on public.friendships;
create policy "friendships_insert_requester" on public.friendships
  for insert with check (
    auth.uid() = requester_id
    and status = 'pending'
    and addressee_id <> auth.uid()
    and not public.is_blocked_between(requester_id, addressee_id)
  );

-- A direct thread is closed while either side has blocked the other (belt and
-- braces: block_user already deleted the friendship the function requires).
create or replace function public.can_post_in_conversation(p_conv uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.direct_conversations c
    where c.id = p_conv
      and p_user in (c.user_a, c.user_b)
      and public.are_friends(c.user_a, c.user_b)
      and not public.is_blocked_between(c.user_a, c.user_b)
  );
$$;

-- Search hides blocked users in both directions.
create or replace function public.search_profiles(p_query text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_id text,
  vehicle_type text
)
language sql stable set search_path = public as $$
  with q as (select btrim(coalesce(p_query, '')) as term)
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_id,
    p.vehicle_type
  from public.profiles p, q
  where char_length(q.term) >= 2
    and p.id <> auth.uid()
    and not public.is_blocked_between(p.id, auth.uid())
    and (
      strpos(lower(p.username), lower(q.term)) > 0
      or p.username % q.term
    )
  order by
    (strpos(lower(p.username), lower(q.term)) > 0) desc,
    similarity(p.username, q.term) desc,
    p.username
  limit 20;
$$;

revoke execute on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated, service_role;
