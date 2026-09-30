-- 0043_direct_messages_and_shares.sql
--
-- Direct (one-to-one) messages, and rich chat messages (photo / location / trip)
-- in every channel kind.
--
--   * direct_conversations: one row per pair of friends. Created only through
--     get_or_create_conversation() (which requires an accepted friendship), read
--     only by its two members.
--   * chat_messages gains conversation_id (a third channel kind), kind and
--     payload. Exactly one of trip_id / group_id / conversation_id is set.
--   * send_chat_message(): the write path for non-text messages. It checks
--     membership, and when a photo is shared it grants the recipients read
--     access to that photo (map_post_shares), so a private pin shared into a
--     chat can actually be opened by the people it was sent to.
--   * my_conversations(): the inbox — each conversation with the other person's
--     public profile and the latest message.
--
-- Safe to re-run.

-- ---------------------------------------------------------------------------
-- Helpers (are_friends only reads friendships, which already exists;
-- is_conversation_member is defined below, once its table exists — a SQL-language
-- function is validated when created, so it can't come first).
-- ---------------------------------------------------------------------------
create or replace function public.are_friends(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = p_a and f.addressee_id = p_b)
        or (f.requester_id = p_b and f.addressee_id = p_a))
  );
$$;

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------
create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  constraint direct_conversations_pair_chk check (user_a < user_b),
  constraint direct_conversations_pair_uniq unique (user_a, user_b)
);

create index if not exists direct_conversations_user_b_idx
  on public.direct_conversations (user_b);

alter table public.direct_conversations enable row level security;

-- Members may read; nobody writes directly (the RPCs below are the only path).
drop policy if exists "direct_conversations_select_member" on public.direct_conversations;
create policy "direct_conversations_select_member" on public.direct_conversations
  for select using (auth.uid() in (user_a, user_b));

revoke insert, update, delete on public.direct_conversations from anon, authenticated;

create or replace function public.is_conversation_member(p_conv uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.direct_conversations c
    where c.id = p_conv and p_user in (c.user_a, c.user_b)
  );
$$;

create or replace function public.get_or_create_conversation(p_other uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_other is null or p_other = v_uid then
    raise exception 'invalid recipient';
  end if;
  if not public.are_friends(v_uid, p_other) then
    raise exception 'You can only message friends.' using errcode = '42501';
  end if;

  v_a := least(v_uid, p_other);
  v_b := greatest(v_uid, p_other);

  insert into public.direct_conversations (user_a, user_b)
  values (v_a, v_b)
  on conflict (user_a, user_b) do nothing;

  select id into v_id from public.direct_conversations
  where user_a = v_a and user_b = v_b;
  return v_id;
end;
$$;

revoke execute on function public.get_or_create_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_conversation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- chat_messages: third channel kind + message kind/payload
-- ---------------------------------------------------------------------------
alter table public.chat_messages
  add column if not exists conversation_id uuid
    references public.direct_conversations (id) on delete cascade,
  add column if not exists kind text not null default 'text',
  add column if not exists payload jsonb;

create index if not exists chat_messages_conversation_idx
  on public.chat_messages (conversation_id, created_at);

alter table public.chat_messages drop constraint if exists chat_messages_one_channel_chk;
alter table public.chat_messages
  add constraint chat_messages_one_channel_chk
  check (
    (trip_id is not null)::int
    + (group_id is not null)::int
    + (conversation_id is not null)::int = 1
  );

alter table public.chat_messages drop constraint if exists chat_messages_kind_chk;
alter table public.chat_messages
  add constraint chat_messages_kind_chk
  check (kind in ('text', 'photo', 'location', 'trip'));

alter table public.chat_messages drop constraint if exists chat_messages_payload_len_chk;
alter table public.chat_messages
  add constraint chat_messages_payload_len_chk
  check (payload is null or char_length(payload::text) <= 4000);

-- A conversation is writable only while its two members are still friends, so
-- unfriending or blocking someone closes the thread to new messages (history
-- stays readable).
create or replace function public.can_post_in_conversation(p_conv uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.direct_conversations c
    where c.id = p_conv
      and p_user in (c.user_a, c.user_b)
      and public.are_friends(c.user_a, c.user_b)
  );
$$;

drop policy if exists "chat_messages_select_member" on public.chat_messages;
create policy "chat_messages_select_member" on public.chat_messages
  for select using (
    (trip_id is not null and public.is_trip_participant(trip_id, auth.uid()))
    or (group_id is not null and public.is_group_member(group_id, auth.uid()))
    or (conversation_id is not null
        and public.is_conversation_member(conversation_id, auth.uid()))
  );

drop policy if exists "chat_messages_insert_sender" on public.chat_messages;
create policy "chat_messages_insert_sender" on public.chat_messages
  for insert with check (
    auth.uid() = sender_id
    and (
      (trip_id is not null and public.is_trip_participant(trip_id, auth.uid()))
      or (group_id is not null and public.is_group_member(group_id, auth.uid()))
      or (conversation_id is not null
          and public.can_post_in_conversation(conversation_id, auth.uid()))
    )
  );

-- Keep the inbox ordered by recent activity.
create or replace function public.touch_conversation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.conversation_id is not null then
    update public.direct_conversations
    set last_message_at = new.created_at
    where id = new.conversation_id;
  end if;
  return new;
end;
$$;

drop trigger if exists chat_messages_touch_conversation on public.chat_messages;
create trigger chat_messages_touch_conversation
  after insert on public.chat_messages
  for each row execute function public.touch_conversation();

-- ---------------------------------------------------------------------------
-- send_chat_message: membership-checked write for rich messages. Idempotent on
-- p_id so an offline replay can't duplicate.
-- ---------------------------------------------------------------------------
create or replace function public.send_chat_message(
  p_id uuid,
  p_trip uuid,
  p_group uuid,
  p_conversation uuid,
  p_kind text,
  p_body text,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_post uuid;
  v_other uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if ((p_trip is not null)::int + (p_group is not null)::int
      + (p_conversation is not null)::int) <> 1 then
    raise exception 'exactly one channel is required';
  end if;
  if p_kind not in ('text', 'photo', 'location', 'trip') then
    raise exception 'unknown message kind';
  end if;

  if p_trip is not null then
    if not public.is_trip_participant(p_trip, v_uid) then
      raise exception 'You are not on that trip.' using errcode = '42501';
    end if;
  elsif p_group is not null then
    if not public.is_group_member(p_group, v_uid) then
      raise exception 'You are not in that group.' using errcode = '42501';
    end if;
  else
    if not public.can_post_in_conversation(p_conversation, v_uid) then
      raise exception 'You can only message friends.' using errcode = '42501';
    end if;
  end if;

  -- Sharing a photo must let its recipients open it. Only the photo's owner can
  -- grant access; anyone else's photo is sent as-is (recipients see it only if
  -- they could already).
  if p_kind = 'photo' then
    if p_conversation is not null then
      select case when c.user_a = v_uid then c.user_b else c.user_a end
        into v_other
      from public.direct_conversations c where c.id = p_conversation;
    end if;

    for v_post in
      select (x ->> 'id')::uuid
      from jsonb_array_elements(coalesce(p_payload -> 'posts', '[]'::jsonb)) x
      where (x ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    loop
      if not exists (
        select 1 from public.map_posts p where p.id = v_post and p.user_id = v_uid
      ) then
        continue;
      end if;

      if p_group is not null then
        insert into public.map_post_shares (post_id, shared_with_group)
        values (v_post, p_group) on conflict do nothing;
      elsif p_conversation is not null then
        insert into public.map_post_shares (post_id, shared_with_user)
        values (v_post, v_other) on conflict do nothing;
      else
        -- Trip members already see a non-private photo pinned to this same trip;
        -- grant the rest explicitly.
        insert into public.map_post_shares (post_id, shared_with_user)
        select v_post, tm.user_id
        from public.trip_members tm
        where tm.trip_id = p_trip
          and tm.invite_status = 'accepted'
          and tm.user_id <> v_uid
          and not exists (
            select 1 from public.map_posts mp
            where mp.id = v_post and mp.trip_id = p_trip
              and mp.visibility in ('group', 'public')
          )
        on conflict do nothing;
      end if;
    end loop;
  end if;

  insert into public.chat_messages
    (id, trip_id, group_id, conversation_id, sender_id, body, kind, payload)
  values
    (v_id, p_trip, p_group, p_conversation, v_uid, p_body, p_kind, p_payload)
  on conflict (id) do nothing;

  return v_id;
end;
$$;

revoke execute on function public.send_chat_message(uuid, uuid, uuid, uuid, text, text, jsonb)
  from public, anon;
grant execute on function public.send_chat_message(uuid, uuid, uuid, uuid, text, text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- my_conversations: the inbox.
-- ---------------------------------------------------------------------------
create or replace function public.my_conversations()
returns table (
  conversation_id uuid,
  other_id uuid,
  username text,
  display_name text,
  avatar_id text,
  last_body text,
  last_kind text,
  last_sender uuid,
  last_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    c.id,
    o.id,
    o.username,
    o.display_name,
    o.avatar_id,
    m.body,
    m.kind,
    m.sender_id,
    coalesce(m.created_at, c.created_at)
  from public.direct_conversations c
  join public.profiles o
    on o.id = case when c.user_a = auth.uid() then c.user_b else c.user_a end
  left join lateral (
    select cm.body, cm.kind, cm.sender_id, cm.created_at
    from public.chat_messages cm
    where cm.conversation_id = c.id
    order by cm.created_at desc
    limit 1
  ) m on true
  where auth.uid() in (c.user_a, c.user_b)
  order by coalesce(m.created_at, c.created_at) desc
  limit 200;
$$;

revoke execute on function public.my_conversations() from public, anon;
grant execute on function public.my_conversations() to authenticated;
