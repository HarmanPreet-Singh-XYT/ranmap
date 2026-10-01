-- Realtime: publish the tables the client keeps live (friend requests, trips,
-- groups, notifications, shares...). Postgres-changes events are filtered by RLS,
-- so each client only receives rows it could already read; the app uses them as
-- "something changed" signals and refetches the affected providers.
do $$
declare
  t text;
begin
  foreach t in array array[
    'friendships', 'groups', 'group_members', 'trips', 'trip_stops',
    'trip_legs', 'trip_expenses', 'trip_checklist_items', 'stop_proposals',
    'stop_votes', 'notifications', 'map_post_shares', 'trip_shares',
    'user_blocks'
  ]
  loop
    if to_regclass('public.' || t) is not null and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
