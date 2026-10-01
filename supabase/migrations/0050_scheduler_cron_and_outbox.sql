-- ---------------------------------------------------------------------------
-- Ranmap migration 0050: start scheduled trips from pg_cron, and fan the
-- "trip started" push out through a durable outbox.
--
-- Before: `ranmap-server` polled `start_due_scheduled_trips()` every 60s and
-- then pushed to members — two steps, so a crash between them silently dropped
-- the notification, and trip auto-start died with the API process.
--
-- Now:
--   * pg_cron calls `start_due_scheduled_trips()` every minute (independent of
--     the API process). Guarded: a no-op if pg_cron isn't installed, matching
--     the location-prune schedule in 0003.
--   * A trigger on `trips.status → 'active'` enqueues a `push_jobs` row for the
--     trip's accepted members — for ANY start (scheduled or a manual "start
--     ride"), which also fixes manual starts never notifying.
--   * `ranmap-server` drains `push_jobs` (retryable), instead of polling the
--     trip table.
--
-- Safe to re-run.
-- ---------------------------------------------------------------------------
-- 1. Schedule the trip auto-start (guarded — pg_cron may be absent).
do $$ begin if exists (
  select 1
  from pg_extension
  where extname = 'pg_cron'
) then perform cron.schedule(
  'ranmap_start_due_scheduled_trips',
  '* * * * *',
  'select public.start_due_scheduled_trips()'
);
end if;
exception
when others then raise notice 'pg_cron scheduling skipped: %',
sqlerrm;
end;
$$;
-- 2. Durable push outbox. Server-only: RLS is enabled with no policies and the
--    client grants are revoked, so only the service role can touch it.
create table if not exists public.push_jobs (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint push_jobs_kind_chk check (kind in ('trip_started')),
  constraint push_jobs_attempts_chk check (attempts >= 0)
);
create index if not exists push_jobs_due_idx on public.push_jobs (completed_at, next_attempt_at);
alter table public.push_jobs enable row level security;
revoke all on public.push_jobs
from anon,
  authenticated;
grant all on public.push_jobs to service_role;
-- 3. Enqueue on any trip start. SECURITY DEFINER so the trigger can insert
--    into the server-only table regardless of the caller.
create or replace function public.enqueue_trip_started_job() returns trigger language plpgsql security definer
set search_path = public as $$
declare v_members uuid [];
begin
select array_agg(m.user_id) into v_members
from public.trip_members m
where m.trip_id = new.id
  and m.invite_status = 'accepted';
insert into public.push_jobs (kind, payload)
values (
    'trip_started',
    jsonb_build_object(
      'trip_id',
      new.id,
      'title',
      new.title,
      'member_ids',
      coalesce(to_jsonb(v_members), '[]'::jsonb)
    )
  );
return new;
end;
$$;
drop trigger if exists trips_enqueue_started_push on public.trips;
create trigger trips_enqueue_started_push
after
update on public.trips for each row
  when (
    new.status = 'active'
    and old.status is distinct
    from 'active'
  ) execute function public.enqueue_trip_started_job();