-- Ranmap migration 0012: text length + numeric bound backstops
--
-- The client enforces these limits for UX (lib/core/util/validation.dart), but a
-- patched client talks to PostgREST directly, so the same bounds need to exist
-- in the database. Without them a modified app can write unbounded text into
-- chat, trip, stop, expense, photo-caption, group and AI rows (storage/abuse).
--
-- Safe to re-run (constraints are dropped/guarded before being re-added; the
-- validation step tolerates pre-existing rows that violate them).

-- ---------------------------------------------------------------------------
-- Text length bounds. Each is added NOT VALID (so a pre-existing oversized row
-- can't fail the migration) and then validated in the guarded loop below.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('profiles',        'profiles_username_len_chk',      $q$char_length(username) between 3 and 24$q$),
      ('profiles',        'profiles_display_name_len_chk',  $q$display_name is null or char_length(display_name) <= 60$q$),
      ('trips',           'trips_title_len_chk',            $q$char_length(title) between 1 and 60$q$),
      ('trips',           'trips_place_name_len_chk',       $q$(origin_name is null or char_length(origin_name) <= 120)
                                                                 and (destination_name is null or char_length(destination_name) <= 120)$q$),
      ('trips',           'trips_route_polyline_len_chk',   $q$route_polyline is null or char_length(route_polyline) <= 200000$q$),
      ('trip_stops',      'trip_stops_name_len_chk',        $q$char_length(name) between 1 and 60$q$),
      ('trip_stops',      'trip_stops_notes_len_chk',       $q$notes is null or char_length(notes) <= 500$q$),
      ('trip_expenses',   'trip_expenses_note_len_chk',     $q$note is null or char_length(note) <= 500$q$),
      ('trip_expenses',   'trip_expenses_amount_max_chk',   $q$amount <= 1000000$q$),
      ('map_posts',       'map_posts_caption_len_chk',      $q$caption is null or char_length(caption) <= 200$q$),
      ('chat_messages',   'chat_messages_body_len_chk',     $q$body is null or char_length(body) <= 4000$q$),
      ('groups',          'groups_name_len_chk',            $q$char_length(name) between 1 and 60$q$),
      ('ai_conversations','ai_conversations_title_len_chk', $q$title is null or char_length(title) <= 200$q$),
      ('ai_messages',     'ai_messages_content_len_chk',    $q$char_length(content) between 1 and 8000$q$),
      ('ai_saved_places', 'ai_saved_places_name_len_chk',   $q$char_length(name) between 1 and 200$q$),
      ('ai_saved_places', 'ai_saved_places_notes_len_chk',  $q$notes is null or char_length(notes) <= 2000$q$)
    ) as t(tbl, conname, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.conname) then
      execute format(
        'alter table public.%I add constraint %I check (%s) not valid',
        c.tbl, c.conname, c.expr
      );
    end if;
  end loop;
end;
$$;

-- Validate the constraints just added (and any re-run). A row that still
-- violates one raises a notice instead of aborting the migration.
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
        'profiles_username_len_chk', 'profiles_display_name_len_chk',
        'trips_title_len_chk', 'trips_place_name_len_chk',
        'trips_route_polyline_len_chk',
        'trip_stops_name_len_chk', 'trip_stops_notes_len_chk',
        'trip_expenses_note_len_chk', 'trip_expenses_amount_max_chk',
        'map_posts_caption_len_chk', 'chat_messages_body_len_chk',
        'groups_name_len_chk', 'ai_conversations_title_len_chk',
        'ai_messages_content_len_chk',
        'ai_saved_places_name_len_chk', 'ai_saved_places_notes_len_chk'
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
-- plan_limit(): fail loudly on an unknown key instead of returning NULL, which
-- a `count >= NULL` comparison would read as "under the limit" (i.e. no cap).
-- Only string literals from the enforcement triggers are ever passed.
-- ---------------------------------------------------------------------------
create or replace function public.plan_limit(p_key text)
returns int language plpgsql immutable as $$
declare
  v_limit int;
begin
  v_limit := case p_key
    when 'trips' then 3
    when 'group_members' then 6
    when 'map_posts' then 25
  end;
  if v_limit is null then
    raise exception 'unknown plan limit key: %', p_key;
  end if;
  return v_limit;
end;
$$;
