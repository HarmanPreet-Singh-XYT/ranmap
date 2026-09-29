-- ---------------------------------------------------------------------------
-- Ranmap migration 0035: audit hardening follow-ups.
--
-- Closes issues found in a full-codebase audit:
--   * map_posts.storage_path was repointable via UPDATE, so a user could make
--     their own post reference (and thus read) another user's private
--     `map-media` object. Storage-path is now non-updatable and the update
--     policy re-checks the folder prefix (mirroring user_documents).
--   * the entitlement predicates (is_pro / trip_has_pro / group_has_pro /
--     is_extreme / group_has_extreme / my_plan) kept the default PUBLIC EXECUTE
--     grant, so `anon` could call them to probe arbitrary accounts' paid state.
--   * group_has_extreme ignored membership status (a *pending* requester could
--     lift a group's ceiling).
--   * the 0033 group-member cap trigger regressed to INSERT-only and counted
--     pending rows, so a full free group rejected pending join requests with a
--     paywall and the approval path was unchecked.
--   * the trip cap was INSERT-only, so a client could flip a completed trip
--     back to `planned` to exceed it.
--   * the count-cap triggers were not concurrency-safe (no lock).
--   * trips INSERT accepted any group_id; a pending invitee could read the
--     whole trip row (route, coordinates); stop_proposals / trip_legs let any
--     member overwrite another member's row; vote_stop_proposal read without a
--     row lock; prune_group_locations had no in-function caller check; and a
--     few client-writable text columns had no length backstop.
--
-- Safe to re-run (constraints guarded; policies/functions dropped or replaced).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- map_posts: storage_path / user_id / trip_id must not be reassigned, and the
-- update policy must re-verify the folder prefix so the storage read policy
-- can't be tricked into exposing another user's object.
-- ---------------------------------------------------------------------------
revoke update on public.map_posts from anon, authenticated;
grant update (point, caption, visibility) on public.map_posts to anon, authenticated;

drop policy if exists "map_posts_update_owner" on public.map_posts;
create policy "map_posts_update_owner" on public.map_posts
  for update using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (storage.foldername(storage_path))[1] = auth.uid()::text
    and (trip_id is null or public.is_trip_participant(trip_id, auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- Entitlement predicates are not for anon. Keep authenticated (RLS policies
-- call them) and service_role (the server) explicitly.
-- ---------------------------------------------------------------------------
revoke execute on function public.is_pro(uuid) from public, anon;
revoke execute on function public.trip_has_pro(uuid) from public, anon;
revoke execute on function public.group_has_pro(uuid) from public, anon;
revoke execute on function public.is_extreme(uuid) from public, anon;
revoke execute on function public.group_has_extreme(uuid) from public, anon;
revoke execute on function public.my_plan() from public, anon;

grant execute on function public.is_pro(uuid) to authenticated, service_role;
grant execute on function public.trip_has_pro(uuid) to authenticated, service_role;
grant execute on function public.group_has_pro(uuid) to authenticated, service_role;
grant execute on function public.is_extreme(uuid) to authenticated, service_role;
grant execute on function public.group_has_extreme(uuid) to authenticated, service_role;
grant execute on function public.my_plan() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- group_has_extreme must only count members who actually joined (matching
-- group_has_pro).
-- ---------------------------------------------------------------------------
create or replace function public.group_has_extreme(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group and public.is_extreme(g.owner_id)
  ) or exists (
    select 1 from public.group_members m
    where m.group_id = p_group
      and m.status = 'active'
      and public.is_extreme(m.user_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- Group-member ceiling (restores the 0026 semantics that 0033 dropped):
--   * active members only
--   * fires on INSERT *and* on the pending -> active transition
--   * pending inserts are never capped (a join request must always queue)
--   * serialized per group so concurrent approvals can't overshoot.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_group_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id) or public.group_has_extreme(new.group_id);
  v_pro boolean := public.is_pro(new.user_id) or public.group_has_pro(new.group_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'group_members_extreme'
         when v_pro then 'group_members_pro'
         else 'group_members' end);
  v_count int;
begin
  -- Pending requests are never capped; only active membership counts.
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('group_members:' || new.group_id::text));

  select count(*) into v_count
  from public.group_members m
  where m.group_id = new.group_id
    and m.status = 'active'
    and m.user_id <> new.user_id;

  if v_count >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: this convoy is capped at % members.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: this convoy is capped at % members. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free groups are limited to % members.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists group_members_free_limit on public.group_members;
create trigger group_members_free_limit
  before insert or update of status on public.group_members
  for each row execute function public.enforce_group_member_limit();

-- ---------------------------------------------------------------------------
-- Active-trip ceiling: also enforced when a trip transitions back into
-- planned/active, and serialized per user.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_trip_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := new.created_by;
  v_extreme boolean := public.is_extreme(new.created_by);
  v_pro boolean := public.is_pro(new.created_by);
  v_limit int := public.plan_limit(
    case when v_extreme then 'trips_extreme'
         when v_pro then 'trips_pro'
         else 'trips' end);
  v_count int;
begin
  if new.status not in ('planned', 'active') then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('trips:' || v_uid::text));

  select count(*) into v_count
  from public.trips t
  where t.created_by = v_uid
    and t.status in ('planned', 'active')
    and t.id <> new.id;

  if v_count >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % active trips.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % active trips. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can plan up to % active trips at once.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trips_free_limit on public.trips;
create trigger trips_free_limit
  before insert or update of status on public.trips
  for each row execute function public.enforce_trip_limit();

-- ---------------------------------------------------------------------------
-- Photo / document / saved-route ceilings: serialized per user so concurrent
-- inserts at the boundary can't both pass.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_map_post_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'map_posts_extreme'
         when v_pro then 'map_posts_pro'
         else 'map_posts' end);
  v_count int;
begin
  perform pg_advisory_xact_lock(hashtext('map_posts:' || new.user_id::text));
  select count(*) into v_count from public.map_posts p where p.user_id = new.user_id;
  if v_count >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % pinned photos.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % pinned photos. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can pin up to % photos.',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_document_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'documents_extreme'
         when v_pro then 'documents_pro'
         else 'documents' end);
  v_count int;
begin
  perform pg_advisory_xact_lock(hashtext('user_documents:' || new.user_id::text));
  select count(*) into v_count from public.user_documents d where d.user_id = new.user_id;
  if v_count >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % documents.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % documents. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can keep up to % document(s).',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_route_template_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_extreme boolean := public.is_extreme(new.user_id);
  v_pro boolean := public.is_pro(new.user_id);
  v_limit int := public.plan_limit(
    case when v_extreme then 'route_templates_extreme'
         when v_pro then 'route_templates_pro'
         else 'route_templates' end);
  v_count int;
begin
  perform pg_advisory_xact_lock(hashtext('route_templates:' || new.user_id::text));
  select count(*) into v_count from public.route_templates t where t.user_id = new.user_id;
  if v_count >= v_limit then
    if v_extreme then
      raise exception 'Plan limit reached: your Extreme plan includes up to % saved routes.',
        v_limit using errcode = 'P0001';
    elsif v_pro then
      raise exception 'Plan limit reached: your Pro plan includes up to % saved routes. Upgrade to Extreme for more.',
        v_limit using errcode = 'P0001';
    end if;
    raise exception 'Ranmap Pro required: free accounts can save up to % route(s).',
      v_limit using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- trips INSERT must not attach to a group the creator isn't in (the RPC
-- already checks this; the direct PostgREST path did not).
-- ---------------------------------------------------------------------------
drop policy if exists "trips_insert_creator" on public.trips;
create policy "trips_insert_creator" on public.trips
  for insert with check (
    auth.uid() = created_by
    and (group_id is null or public.is_group_member(group_id, auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- A pending invitee may read the invite card — not the whole trip row.
-- Restrict SELECT to actual participants and expose the (redacted) invite
-- details through a SECURITY DEFINER RPC.
-- ---------------------------------------------------------------------------
drop policy if exists "trips_select_member" on public.trips;
create policy "trips_select_member" on public.trips
  for select using (public.is_trip_participant(id, auth.uid()));

create or replace function public.my_trip_invites()
returns table (trip_id uuid, invite_status text, trips jsonb)
language sql stable security definer set search_path = public as $$
  select
    m.trip_id,
    m.invite_status,
    (to_jsonb(t) - 'origin_point' - 'destination_point' - 'route_polyline')
      || jsonb_build_object(
           'creator',
           (select to_jsonb(p) - 'phone_number' - 'socials'
            from public.profiles p where p.id = t.created_by)
         )
  from public.trip_members m
  join public.trips t on t.id = m.trip_id
  where m.user_id = auth.uid()
    and m.invite_status = 'invited';
$$;

revoke execute on function public.my_trip_invites() from public, anon;
grant execute on function public.my_trip_invites() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- stop_proposals: only the proposer may edit their own proposal (promotion is
-- done inside the SECURITY DEFINER vote RPC, which bypasses RLS).
-- ---------------------------------------------------------------------------
drop policy if exists "stop_proposals_update_creator_or_member" on public.stop_proposals;
create policy "stop_proposals_update_creator" on public.stop_proposals
  for update using (created_by = auth.uid())
  with check (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- trip_legs: shared editing is intentional (any participant may record/adjust
-- legs via the client's upsert). A column-level UPDATE grant would break that
-- upsert — PostgREST emits `do update set created_by = excluded.created_by`,
-- which needs UPDATE on created_by — so the table-level grant from 0016 is
-- left as-is.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- vote_stop_proposal: lock the proposal row so two concurrent votes can't both
-- miss a promotion.
-- ---------------------------------------------------------------------------
create or replace function public.vote_stop_proposal(
  p_proposal uuid,
  p_approve boolean
)
returns public.stop_proposals
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_prop public.stop_proposals;
  v_members bigint;
  v_approvals bigint;
  v_next_sort integer;
  v_point geography;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_prop from public.stop_proposals where id = p_proposal for update;
  if not found then
    raise exception 'proposal not found';
  end if;

  if not exists (
    select 1 from public.trip_members m
    where m.trip_id = v_prop.trip_id and m.user_id = v_uid
  ) then
    raise exception 'not a member of this trip';
  end if;

  insert into public.stop_votes (proposal_id, user_id, approve)
  values (p_proposal, v_uid, coalesce(p_approve, false))
  on conflict (proposal_id, user_id) do update
    set approve = excluded.approve, created_at = now();

  select count(*) into v_members
  from public.trip_members m where m.trip_id = v_prop.trip_id;

  select count(*) into v_approvals
  from public.stop_votes v where v.proposal_id = p_proposal and v.approve;

  if v_prop.status = 'open' and v_approvals * 2 > v_members then
    v_point := case
      when v_prop.lat is not null and v_prop.lng is not null
        then ST_SetSRID(ST_MakePoint(v_prop.lng, v_prop.lat), 4326)::geography
      else (
        select coalesce(t.destination_point, t.origin_point)
        from public.trips t where t.id = v_prop.trip_id
      )
    end;

    if v_point is not null then
      update public.stop_proposals
      set status = 'approved'
      where id = p_proposal and status = 'open'
      returning * into v_prop;

      if found then
        select coalesce(max(s.sort_order), -1) + 1 into v_next_sort
        from public.trip_stops s where s.trip_id = v_prop.trip_id;

        insert into public.trip_stops (trip_id, created_by, kind, name, point, notes, sort_order)
        values (
          v_prop.trip_id, v_prop.created_by, 'custom', v_prop.name, v_point, v_prop.note, v_next_sort
        );
      end if;
    end if;
  end if;

  return v_prop;
end;
$$;

-- ---------------------------------------------------------------------------
-- prune_group_locations: internal caller check (defence in depth on top of the
-- REVOKE), matching prune_location_pings.
-- ---------------------------------------------------------------------------
create or replace function public.prune_group_locations(p_keep_minutes integer default 60)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_deleted integer;
begin
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'not authorized';
  end if;

  delete from public.group_locations
  where updated_at < now() - make_interval(mins => greatest(p_keep_minutes, 1));
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function public.prune_group_locations(integer) from public, anon, authenticated;
grant execute on function public.prune_group_locations(integer) to service_role;

-- ---------------------------------------------------------------------------
-- support_requests: a submitter may only attribute a request to themselves.
-- ---------------------------------------------------------------------------
drop policy if exists "support_requests_insert" on public.support_requests;
create policy "support_requests_insert" on public.support_requests
  for insert
  to anon, authenticated
  with check (user_id is null or user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Length backstops on client-writable text columns that 0012/0026 missed.
-- NOT VALID so a pre-existing oversized row can't block the migration.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('profiles',        'profiles_avatar_len_chk',         $q$avatar_id is null or char_length(avatar_id) <= 512$q$),
      ('map_posts',       'map_posts_storage_path_len_chk',  $q$char_length(storage_path) <= 512$q$),
      ('user_documents',  'user_documents_storage_len_chk',  $q$char_length(storage_path) <= 512$q$),
      ('chat_messages',   'chat_messages_attachment_len_chk', $q$attachment_path is null or char_length(attachment_path) <= 512$q$)
    ) as t(tbl, conname, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.conname) then
      execute format('alter table public.%I add constraint %I check (%s) not valid', c.tbl, c.conname, c.expr);
    end if;
  end loop;
end;
$$;

do $$
declare
  c record;
begin
  for c in
    select conname, conrelid::regclass::text as tbl
    from pg_constraint
    where connamespace = 'public'::regnamespace
      and contype = 'c'
      and convalidated = false
      and conname in (
        'profiles_avatar_len_chk', 'map_posts_storage_path_len_chk',
        'user_documents_storage_len_chk', 'chat_messages_attachment_len_chk'
      )
  loop
    begin
      execute format('alter table %s validate constraint %I', c.tbl, c.conname);
    exception when others then
      raise notice 'constraint % not validated (existing rows violate it): %', c.conname, sqlerrm;
    end;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic reservation for token metering.
--
-- The AI allowance is metered in tokens, which are only known *after* the
-- model responds, so `consume_usage` (one unit) can't bound it: N concurrent
-- requests all read the same "used" and all proceed. `reserve_usage` adds an
-- up-front upper-bound cost atomically (row-locked, same as consume_usage) and
-- refuses if it would exceed the ceiling; the route refunds the unused part
-- with `release_usage` once the real token count is known. That keeps
-- concurrent turns from overshooting the cap by more than one request.
-- ---------------------------------------------------------------------------
create or replace function public.reserve_usage(
  p_user uuid,
  p_feature text,
  p_units int,
  p_max int,
  p_window_seconds int
)
returns table (allowed boolean, used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_units int := greatest(coalesce(p_units, 0), 0);
begin
  insert into public.usage_counters (user_id, feature, window_start, count)
  values (p_user, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  end if;

  if v_count + v_units > p_max then
    update public.usage_counters set window_start = v_start, count = v_count
    where user_id = p_user and feature = p_feature;
    return query select false, v_count, v_start;
    return;
  end if;

  v_count := v_count + v_units;
  update public.usage_counters set window_start = v_start, count = v_count
  where user_id = p_user and feature = p_feature;
  return query select true, v_count, v_start;
end;
$$;

revoke all on function public.reserve_usage(uuid, text, int, int, int) from public, anon, authenticated;
grant execute on function public.reserve_usage(uuid, text, int, int, int) to service_role;

-- Refunds a reservation that wasn't fully spent. Never goes below zero, and a
-- rolled window means there is nothing to refund.
create or replace function public.release_usage(
  p_user uuid,
  p_feature text,
  p_units int,
  p_window_seconds int
)
returns table (used int, window_start timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_start timestamptz;
  v_count int;
  v_units int := greatest(coalesce(p_units, 0), 0);
begin
  select uc.window_start, uc.count into v_start, v_count
  from public.usage_counters uc
  where uc.user_id = p_user and uc.feature = p_feature
  for update;

  if not found then
    return query select 0, v_now;
    return;
  end if;

  if v_start + make_interval(secs => p_window_seconds) <= v_now then
    v_start := v_now;
    v_count := 0;
  else
    v_count := greatest(v_count - v_units, 0);
  end if;

  update public.usage_counters set window_start = v_start, count = v_count
  where user_id = p_user and feature = p_feature;
  return query select v_count, v_start;
end;
$$;

revoke all on function public.release_usage(uuid, text, int, int) from public, anon, authenticated;
grant execute on function public.release_usage(uuid, text, int, int) to service_role;
