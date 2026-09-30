-- 0047_terms_acceptance.sql
--
-- Records when a user accepted the Terms of Service and Privacy Policy, so
-- consent is stored rather than implied (App Store 1.2 / Play UGC). The sign-up
-- screen requires the checkbox before an account can be created.
--
-- The column defaults to the row's creation time, so new profiles are stamped
-- automatically and existing rows are backfilled with the migration time —
-- nobody already using the app is pushed back to a re-accept screen.

alter table public.profiles
  add column if not exists terms_accepted_at timestamptz not null default now();
