-- Ranmap plan / free-tier limit test suite (pgTAP).
--
-- Run with the Supabase CLI:  supabase test db
--
-- Covers 0009_plans.sql and 0010_plan_limits.sql: the entitlement predicates,
-- the free count caps (and that Pro lifts them), the shared usage meter, and
-- that the plan column / meter stay out of clients' reach.

begin;

select plan(15);

-- ---------------------------------------------------------------------------
-- Fixtures. alice / bob / carol plus seven plain members for the group cap.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, encrypted_password, email_confirmed_at)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.dev', 'x', now()),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.dev', 'x', now()),
  ('33333333-3333-3333-3333-333333333333', 'carol@test.dev', 'x', now());

insert into auth.users (id, email, encrypted_password, email_confirmed_at)
select ('00000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'm' || g || '@test.dev', 'x', now()
from generate_series(1, 7) g;

insert into public.profiles (id, username)
values
  ('11111111-1111-1111-1111-111111111111', 'alice_plans'),
  ('22222222-2222-2222-2222-222222222222', 'bob_plans'),
  ('33333333-3333-3333-3333-333333333333', 'carol_plans');

insert into public.profiles (id, username)
select ('00000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'm' || g
from generate_series(1, 7) g;

-- ---------------------------------------------------------------------------
-- is_pro
-- ---------------------------------------------------------------------------
select is(
  public.is_pro('00000000-0000-0000-0000-000000000002'),
  false,
  'a fresh account is not Pro'
);

update public.profiles set plan = 'pro' where id = '33333333-3333-3333-3333-333333333333';
select is(
  public.is_pro('33333333-3333-3333-3333-333333333333'),
  true,
  'plan = pro with no expiry is Pro'
);

update public.profiles
  set plan = 'pro', plan_expires_at = now() - interval '1 day'
  where id = '22222222-2222-2222-2222-222222222222';
select is(
  public.is_pro('22222222-2222-2222-2222-222222222222'),
  false,
  'an expired Pro plan is not Pro'
);

-- ---------------------------------------------------------------------------
-- Trip cap (alice is free here)
-- ---------------------------------------------------------------------------
insert into public.trips (created_by, title)
values
  ('11111111-1111-1111-1111-111111111111', 'A1'),
  ('11111111-1111-1111-1111-111111111111', 'A2'),
  ('11111111-1111-1111-1111-111111111111', 'A3');

select throws_ok(
  $$ insert into public.trips (created_by, title)
     values ('11111111-1111-1111-1111-111111111111', 'A4') $$,
  'P0001',
  null,
  'a free account is capped at 3 active trips'
);

update public.profiles set plan = 'pro' where id = '11111111-1111-1111-1111-111111111111';
select lives_ok(
  $$ insert into public.trips (created_by, title)
     values ('11111111-1111-1111-1111-111111111111', 'A5') $$,
  'Pro lifts the trip cap'
);

select is(
  public.trip_has_pro((select id from public.trips
                        where created_by = '11111111-1111-1111-1111-111111111111'
                        limit 1)),
  true,
  'a trip with a Pro member is Pro-enabled'
);

-- ---------------------------------------------------------------------------
-- Photo cap (bob is free — his Pro plan expired above)
-- ---------------------------------------------------------------------------
insert into public.map_posts (user_id, point, storage_path)
select '22222222-2222-2222-2222-222222222222', 'POINT(0 0)'::geography, 'bob/' || g
from generate_series(1, 25) g;

select throws_ok(
  $$ insert into public.map_posts (user_id, point, storage_path)
     values ('22222222-2222-2222-2222-222222222222', 'POINT(1 1)'::geography, 'bob/extra') $$,
  'P0001',
  null,
  'a free account is capped at 25 pinned photos'
);

-- ---------------------------------------------------------------------------
-- Group size cap (all members free at first)
-- ---------------------------------------------------------------------------
insert into public.groups (id, name, owner_id)
values ('aaaaaaaa-0000-0000-0000-000000000000', 'Crew',
        '00000000-0000-0000-0000-000000000001');

insert into public.group_members (group_id, user_id)
select 'aaaaaaaa-0000-0000-0000-000000000000',
       ('00000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid
from generate_series(1, 6) g;

select throws_ok(
  $$ insert into public.group_members (group_id, user_id)
     values ('aaaaaaaa-0000-0000-0000-000000000000',
             '00000000-0000-0000-0000-000000000007') $$,
  'P0001',
  null,
  'a free group is capped at 6 members'
);

-- Promotion of any member unlocks the whole group ("travel together").
update public.profiles set plan = 'pro' where id = '00000000-0000-0000-0000-000000000001';
select lives_ok(
  $$ insert into public.group_members (group_id, user_id)
     values ('aaaaaaaa-0000-0000-0000-000000000000',
             '00000000-0000-0000-0000-000000000007') $$,
  'a Pro member lifts the group cap'
);

-- ---------------------------------------------------------------------------
-- Shared usage meter
-- ---------------------------------------------------------------------------
select is(
  public.consume_usage('00000000-0000-0000-0000-000000000003', 'maps_search', 1, 3600),
  true,
  'consume_usage allows the first use'
);
select is(
  public.consume_usage('00000000-0000-0000-0000-000000000003', 'maps_search', 1, 3600),
  false,
  'consume_usage blocks once max is reached'
);

-- ---------------------------------------------------------------------------
-- Privileges / lockdown
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  (select plan from public.my_plan()),
  'pro',
  'my_plan returns the caller''s plan'
);

select throws_ok(
  $$ update public.profiles set plan = 'pro'
     where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501',
  null,
  'a client cannot set its own plan'
);

reset role;

select ok(
  (select relrowsecurity from pg_class where oid = 'public.usage_counters'::regclass),
  'RLS is enabled on usage_counters'
);

select ok(
  not has_function_privilege('anon', 'public.consume_usage(uuid,text,integer,integer)', 'execute'),
  'anon cannot execute consume_usage'
);

select * from finish();

rollback;
