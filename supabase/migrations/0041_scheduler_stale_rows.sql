-- 0041_scheduler_stale_rows.sql
--
-- start_due_scheduled_trips() only matches trips still in 'planned', so a
-- schedule row for a trip that was started (or completed) by hand was never
-- deleted and lingered forever. Sweep those rows at the start of every run.
-- Everything else is identical to 0038; safe to re-run.

create or replace function public.start_due_scheduled_trips()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_started jsonb := '[]'::jsonb;
  r record;
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'not authorized';
  end if;

  delete from public.scheduled_trips st
  using public.trips t
  where t.id = st.trip_id and t.status <> 'planned';

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
grant execute on function public.start_due_scheduled_trips() to service_role;
