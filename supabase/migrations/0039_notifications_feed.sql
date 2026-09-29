-- 0039_notifications_feed.sql
--
-- An in-app notification feed. Push (firebase) delivers to a device's OS tray
-- and is never retained; this table is the durable, listable record so the app
-- can show a "Notifications" inbox of everything the user was told about.
--
-- Rows are written only by ranmap-server (the same `notifyUsers` call that
-- sends the push — see server/src/lib/push.ts), so a client can't fabricate a
-- notification. The owner reads them and marks/deletes their own.

create table if not exists public.notifications (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  -- The same payload the push carries (type + tripId/groupId/alert kind), used
  -- to route a tap to the relevant screen.
  data       jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_kind_chk check (
    kind in ('trip_invites', 'chat_messages', 'trip_updates', 'group_invites', 'convoy_alerts')
  ),
  constraint notifications_title_len_chk check (char_length(title) between 1 and 200),
  constraint notifications_body_len_chk check (body is null or char_length(body) <= 1000)
);

-- The inbox reads newest-first per user; this index also serves the unread count.
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- Supabase grants ALL on new public tables to anon/authenticated by default;
-- supersede it with exactly what each role needs. No client INSERT: rows are
-- server-authored only (service_role).
revoke all on public.notifications from anon, authenticated;
grant select, update, delete on public.notifications to authenticated;
grant all on public.notifications to service_role;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (auth.uid() = user_id);

-- Only read_at (and other own fields) may be updated, and only on your own rows.
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications
  for delete using (auth.uid() = user_id);
