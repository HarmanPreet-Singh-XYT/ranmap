-- 0011_notifications.sql
--
-- Push notification plumbing: per-device delivery tokens and per-user
-- notification preferences. Delivery itself happens in ranmap-server (see
-- server/src/lib/push.ts); the app only registers its token through the server
-- and edits its own preferences.

-- Device tokens.
--
-- Written only by ranmap-server using the secret key: the client POSTs its
-- token to /notifications/register and the server upserts it here. RLS is
-- enabled with NO policies, and we revoke the default table grants Supabase
-- adds to anon/authenticated, so no client can read or write this table.
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  platform   text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_tokens_platform_chk check (platform in ('ios', 'android', 'web'))
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Per-user notification preferences. A missing row means "all on" (the server
-- defaults to sending), so an account that never opens Settings still gets
-- notifications. Owners manage only their own row.
create table if not exists public.notification_prefs (
  user_id       uuid primary key references public.profiles (id) on delete cascade,
  trip_invites  boolean not null default true,
  chat_messages boolean not null default true,
  trip_updates  boolean not null default true,
  updated_at    timestamptz not null default now()
);

alter table public.notification_prefs enable row level security;

-- Supabase grants ALL on new public tables to anon/authenticated by default;
-- supersede that with exactly what each role needs.
revoke all on public.device_tokens from anon, authenticated;
revoke all on public.notification_prefs from anon, authenticated;
grant select, insert, update on public.notification_prefs to authenticated;
grant all on public.device_tokens to service_role;
grant all on public.notification_prefs to service_role;

drop policy if exists "notification_prefs_select_own" on public.notification_prefs;
create policy "notification_prefs_select_own" on public.notification_prefs
  for select using (auth.uid() = user_id);

drop policy if exists "notification_prefs_insert_own" on public.notification_prefs;
create policy "notification_prefs_insert_own" on public.notification_prefs
  for insert with check (auth.uid() = user_id);

drop policy if exists "notification_prefs_update_own" on public.notification_prefs;
create policy "notification_prefs_update_own" on public.notification_prefs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
