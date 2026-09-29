-- 0038_notification_convoy_alerts_and_trip_start.sql
--
-- Two notification gaps this closes:
--
--   * `convoy_alerts` — a distinct opt-out for convoy SOS / regroup alerts.
--     They were delivered under the `group_invites` preference, so muting group
--     invites also silenced emergency alerts (and vice-versa).
--
--   * `start_due_scheduled_trips` now returns which trips it actually started
--     (with their accepted members) instead of a bare count, so the server can
--     push a "trip started" notification under the `trip_updates` preference —
--     that toggle previously saved but was never consumed.

-- Per-user opt-out for convoy alerts. Defaults on, like every other kind, so an
-- account that never opens Settings still receives SOS pushes.
alter table public.notification_prefs
  add column if not exists convoy_alerts boolean not null default true;

-- The return type changes from integer to jsonb, so the old signature must be
-- dropped before the new one can be created.
drop function if exists public.start_due_scheduled_trips();

create function public.start_due_scheduled_trips()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_started jsonb := '[]'::jsonb;
  r record;
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'not authorized';
  end if;

  for r in
    select st.id as schedule_id, st.trip_id, t.title
    from public.scheduled_trips st
    join public.trips t on t.id = st.trip_id
    where st.scheduled_for <= now() and t.status = 'planned'
    for update of st skip locked
  loop
    update public.trips
    set status = 'active', started_at = now()
    where id = r.trip_id and status = 'planned';
    if found then
      delete from public.scheduled_trips where id = r.schedule_id;
      v_started := v_started || jsonb_build_object(
        'trip_id', r.trip_id,
        'title', r.title,
        'member_ids', coalesce(
          (
            select jsonb_agg(tm.user_id)
            from public.trip_members tm
            where tm.trip_id = r.trip_id and tm.invite_status = 'accepted'
          ),
          '[]'::jsonb
        )
      );
    end if;
  end loop;
  return v_started;
end;
$$;

revoke execute on function public.start_due_scheduled_trips() from public, anon, authenticated;
