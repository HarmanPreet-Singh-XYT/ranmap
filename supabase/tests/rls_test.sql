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

-- 29 assertions: 24 ok() (RLS + RPC/column privilege grants) plus five
-- behavioural checks (lives_ok / throws_ok / is_empty) below.
select plan(29);

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
        'ai_conversations', 'ai_messages', 'ai_saved_places', 'scheduled_trips',
        'group_locations', 'group_alerts', 'alert_checkins',
        'trip_checklist_items', 'route_templates', 'trip_shares',
        'vehicle_service', 'user_documents'
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
    'public.create_trip(text, uuid, timestamptz, text, double precision, double precision, text, double precision, double precision, text, uuid, text)',
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
  not has_function_privilege('authenticated', 'public.usage_status(uuid, text, integer)', 'execute'),
  'authenticated cannot execute usage_status'
);
select ok(
  not has_function_privilege('authenticated', 'public.reserve_usage(uuid, text, integer, integer, integer)', 'execute'),
  'authenticated cannot execute reserve_usage'
);
select ok(
  not has_function_privilege('authenticated', 'public.settle_usage(uuid, text, integer, integer, integer)', 'execute'),
  'authenticated cannot execute settle_usage'
);
select ok(
  not has_function_privilege('authenticated', 'public.consume_rate_limit(text, integer, integer)', 'execute'),
  'authenticated cannot execute consume_rate_limit'
);
select ok(
  not has_function_privilege('authenticated', 'public.start_due_scheduled_trips()', 'execute'),
  'authenticated cannot execute start_due_scheduled_trips'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.broadcast_position(uuid, double precision, double precision, double precision, double precision)',
    'execute'
  ),
  'anon cannot execute broadcast_position'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.broadcast_position(uuid, double precision, double precision, double precision, double precision)',
    'execute'
  ),
  'authenticated can execute broadcast_position'
);

-- ---------------------------------------------------------------------------
-- Group membership (0026): join codes are authenticated-only, the invite-code
-- generator stays private, and roles are RPC-only (no client UPDATE grant).
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'public.join_group(text)', 'execute'),
  'anon cannot execute join_group'
);
select ok(
  has_function_privilege('authenticated', 'public.join_group(text)', 'execute'),
  'authenticated can execute join_group'
);
select ok(
  not has_function_privilege('authenticated', 'public.random_invite_code()', 'execute'),
  'authenticated cannot call the invite-code generator directly'
);
select ok(
  not has_column_privilege('authenticated', 'public.group_members', 'role', 'update'),
  'authenticated cannot UPDATE group_members.role'
);
select ok(
  not has_column_privilege('authenticated', 'public.group_members', 'status', 'update'),
  'authenticated cannot UPDATE group_members.status'
);

-- ---------------------------------------------------------------------------
-- Group convoy (0027): the group location stream is authenticated-only, the
-- presence prune is server-only, and alerts are RPC-only (no direct writes).
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege(
    'anon',
    'public.broadcast_group_position(uuid, double precision, double precision, double precision, double precision, boolean)',
    'execute'
  ),
  'anon cannot execute broadcast_group_position'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.broadcast_group_position(uuid, double precision, double precision, double precision, double precision, boolean)',
    'execute'
  ),
  'authenticated can execute broadcast_group_position'
);
select ok(
  not has_function_privilege('authenticated', 'public.prune_group_locations(integer)', 'execute'),
  'authenticated cannot execute prune_group_locations'
);
select ok(
  not has_table_privilege('authenticated', 'public.group_alerts', 'insert'),
  'authenticated cannot INSERT group_alerts directly'
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

-- A trip and a group with known ids, seeded as the superuser (RLS bypassed)
-- before switching roles. The behavioural tests below need to attempt an
-- insert against a row the actor cannot *see* — selecting the id from the
-- table would return zero rows for a non-member and never exercise the policy
-- at all.
insert into public.trips (id, created_by, title)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 'Seeded trip');
insert into public.groups (id, name, owner_id)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Seeded group',
        '11111111-1111-1111-1111-111111111111');

-- As alice: creating a trip should succeed.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select lives_ok(
  $$ select public.create_trip('Audit trip') $$,
  'a signed-in user can create a trip'
);

-- p_user is the AI server's service-role escape hatch (0018). A normal
-- authenticated caller must not be able to forge another user's identity.
select throws_ok(
  $$ select public.create_trip('Forged', p_user => '22222222-2222-2222-2222-222222222222') $$,
  'not authorized to specify a user',
  'an authenticated user cannot pass create_trip.p_user'
);

-- As bob (not a member): cannot see alice's trip, and cannot self-join it.
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is_empty(
  $$ select 1 from public.trips $$,
  'a non-member cannot read a trip they are not on'
);
select throws_ok(
  $$ insert into public.trip_members (trip_id, user_id, invite_status)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
             '22222222-2222-2222-2222-222222222222', 'accepted') $$,
  '42501',
  null,
  'a non-member cannot insert themselves as a trip member'
);

-- Same for a group (0026): joining is join_group() / an admin, never a
-- client-side self-insert.
select throws_ok(
  $$ insert into public.group_members (group_id, user_id, role, status)
     values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
             '22222222-2222-2222-2222-222222222222', 'member', 'active') $$,
  '42501',
  null,
  'a non-member cannot insert themselves into a group'
);

reset role;

select * from finish();

rollback;
