-- ---------------------------------------------------------------------------
-- Ranmap migration 0031: support request inbox.
--
-- Backs the web contact form (web-app: app/support/page.tsx). Anyone can
-- submit — signed in or not — but nobody can read their own submission back;
-- this is an insert-only mailbox, triaged by staff via the Supabase
-- dashboard or a future admin view, not by the submitter's own session.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------
create table if not exists public.support_requests (
  id uuid primary key default uuid_generate_v4(),
  -- Nullable: the web contact form doesn't require sign-in.
  user_id uuid references public.profiles (id) on delete set null,
  name text not null,
  email text not null,
  category text not null,
  message text not null,
  created_at timestamptz not null default now(),
  constraint support_requests_name_chk check (char_length(name) between 1 and 120),
  constraint support_requests_email_chk check (char_length(email) between 3 and 254),
  constraint support_requests_category_chk check (char_length(category) between 1 and 60),
  constraint support_requests_message_chk check (char_length(message) between 1 and 4000)
);

alter table public.support_requests enable row level security;

-- Insert-only for everyone (anon + authenticated); no select/update/delete
-- policy exists, so only the service role (staff tooling) can read rows back.
drop policy if exists "support_requests_insert" on public.support_requests;
create policy "support_requests_insert" on public.support_requests
  for insert
  to anon, authenticated
  with check (true);
