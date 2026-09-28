-- ---------------------------------------------------------------------------
-- Ranmap migration 0030: vehicle service reminders + a personal document wallet.
--
--   * `vehicle_service` — one row per user: the service interval and the
--     odometer at the last service. The odometer itself is derived from the
--     trip distance the app already records, so a "service due in N km" reminder
--     needs no manual mileage entry.
--   * `documents` storage bucket (private) + `user_documents` — a private
--     wallet for license / insurance / tickets, available offline.
--
-- Both are strictly per-user (owner-only RLS).
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Vehicle service reminder.
-- ---------------------------------------------------------------------------
create table if not exists public.vehicle_service (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  interval_km numeric not null default 10000,
  last_service_km numeric not null default 0,
  updated_at timestamptz not null default now(),
  constraint vehicle_service_interval_chk check (interval_km > 0 and interval_km <= 200000),
  constraint vehicle_service_last_chk check (last_service_km >= 0)
);

alter table public.vehicle_service enable row level security;

drop policy if exists "vehicle_service_owner" on public.vehicle_service;
create policy "vehicle_service_owner" on public.vehicle_service
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Document wallet. Files live in a private `documents` bucket under the
-- owner's own folder; the row carries the metadata.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

create table if not exists public.user_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  kind text not null default 'other',
  storage_path text not null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint user_documents_kind_chk
    check (kind in ('license', 'insurance', 'ticket', 'registration', 'other')),
  constraint user_documents_name_len_chk check (char_length(name) between 1 and 80)
);

create index if not exists user_documents_user_idx
  on public.user_documents (user_id, created_at desc);

alter table public.user_documents enable row level security;

-- Owner-only, and the stored path must sit under the owner's own folder so the
-- storage read policy can't be tricked into exposing another user's file.
drop policy if exists "user_documents_owner" on public.user_documents;
create policy "user_documents_owner" on public.user_documents
  for all using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (storage.foldername(storage_path))[1] = auth.uid()::text
  );

-- Private bucket: readable/writable only by the owner.
drop policy if exists "documents_select_own" on storage.objects;
create policy "documents_select_own" on storage.objects
  for select using (
    bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "documents_insert_own" on storage.objects;
create policy "documents_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "documents_update_own" on storage.objects;
create policy "documents_update_own" on storage.objects
  for update using (
    bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "documents_delete_own" on storage.objects;
create policy "documents_delete_own" on storage.objects
  for delete using (
    bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text
  );
