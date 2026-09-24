-- Ranmap RLS / privilege test suite (pgTAP).
--
-- Run with the Supabase CLI:  supabase test db
-- (Requires Docker; the CLI spins up a local Postgres, applies the migrations
-- in supabase/migrations, then runs every file in supabase/tests.)
--
-- Covers the invariants the security audit flagged as untested: RLS is on for
-- every app table, the RPC EXECUTE grants are what 0007/0008 intend, anon
-- can't reach the privileged functions, and a non-member can't self-join a
-- trip or read a trip they aren't on.

begin;

select plan(12);

-- ---------------------------------------------------------------------------
-- RLS is enabled on every application table (catches a new table added without
-- `alter table ... enable row level security`).
-- ---------------------------------------------------------------------------
select ok(
  (
    select bool_and(c.relrowsecurity)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relname in (
        'profiles', 'friendships', 'groups', 'group_members', 'trips',
        'trip_members', 'trip_stops', 'location_pings', 'trip_stats',
        'trip_expenses', 'map_posts', 'map_post_shares', 'chat_messages',
        'ai_conversations', 'ai_messages', 'ai_saved_places', 'scheduled_trips'
      )
  ),
  'RLS is enabled on every application table'
);

-- ---------------------------------------------------------------------------
-- RPC EXECUTE grants (0007 / 0008).
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'public.create_group(text)', 'execute'),
  'anon cannot execute create_group'
);
select ok(
  has_function_privilege('authenticated', 'public.create_group(text)', 'execute'),
  'authenticated can execute create_group'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_trip(text, uuid, timestamptz, text, double precision, double precision, text, double precision, double precision, text)',
    'execute'
  ),
  'anon cannot execute create_trip'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.update_trip_route(uuid, text, double precision, double precision, text, double precision, double precision, text)',
    'execute'
  ),
  'anon cannot execute update_trip_route'
);
select ok(
  not has_function_privilege('authenticated', 'public.prune_location_pings(integer)', 'execute'),
  'authenticated cannot execute prune_location_pings'
);
select ok(
  not has_function_privilege('authenticated', 'public.start_due_scheduled_trips()', 'execute'),
  'authenticated cannot execute start_due_scheduled_trips'
);

-- ---------------------------------------------------------------------------
-- Column-level grants on profiles (0005 / 0007): phone_verified must never be
-- client-writable, while ordinary columns are.
-- ---------------------------------------------------------------------------
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'phone_verified', 'insert'),
  'authenticated cannot INSERT profiles.phone_verified'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'username', 'insert'),
  'authenticated can INSERT profiles.username'
);

-- ---------------------------------------------------------------------------
-- Behavioural checks with two users.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, encrypted_password, email_confirmed_at)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev', 'x', now()),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev', 'x', now());

insert into public.profiles (id, username)
values
  ('11111111-1111-1111-1111-111111111111', 'alice_t'),
  ('22222222-2222-2222-2222-222222222222', 'bob_t');

-- As alice: creating a trip should succeed.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select lives_ok(
  $$ select public.create_trip('Audit trip') $$,
  'a signed-in user can create a trip'
);

-- As bob (not a member): cannot see alice's trip, and cannot self-join it.
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is_empty(
  $$ select 1 from public.trips $$,
  'a non-member cannot read a trip they are not on'
);
select throws_ok(
  $$ insert into public.trip_members (trip_id, user_id, invite_status)
     select id, '22222222-2222-2222-2222-222222222222', 'accepted' from public.trips $$,
  '42501',
  null,
  'a non-member cannot insert themselves as a trip member'
);

reset role;

select * from finish();

rollback;
