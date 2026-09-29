-- 0037_convoy_quick_status_alerts.sql
--
-- 0028 widened the `group_alerts_kind_chk` constraint to allow the quick convoy
-- statuses (wait / stopping / fuel), but `send_group_alert` kept its own copy of
-- the allowlist and still rejected them with "unknown alert kind". Bring the RPC
-- in line with the constraint.
--
-- Safe to re-run.

create or replace function public.send_group_alert(
  p_group uuid,
  p_kind text,
  p_message text default null,
  p_lat double precision default null,
  p_lng double precision default null
)
returns public.group_alerts
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_alert public.group_alerts;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_group_member(p_group, v_uid) then
    raise exception 'not a member of this group';
  end if;
  if p_kind not in ('sos', 'regroup', 'arrived', 'departed', 'wait', 'stopping', 'fuel') then
    raise exception 'unknown alert kind';
  end if;
  if p_message is not null and char_length(p_message) > 200 then
    raise exception 'message is too long';
  end if;
  if (p_lat is null) <> (p_lng is null) then
    raise exception 'both coordinates are required together';
  end if;

  insert into public.group_alerts (group_id, created_by, kind, message, point)
  values (
    p_group, v_uid, p_kind, nullif(btrim(coalesce(p_message, '')), ''),
    case when p_lat is not null and p_lng is not null
      then ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography end
  )
  returning * into v_alert;

  return v_alert;
end;
$$;
