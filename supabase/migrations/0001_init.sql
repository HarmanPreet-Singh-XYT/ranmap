-- Ranmap initial schema
-- Run via: supabase db push  (or paste into the Supabase SQL editor)

create extension if not exists "uuid-ossp";
create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar_id text not null default 'default',
  vehicle_type text not null default 'car', -- car | bike | other
  phone_number text unique,
  socials jsonb not null default '{}'::jsonb, -- { "instagram": "...", "x": "..." }
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index profiles_username_lower_idx on public.profiles (lower(username));

-- ---------------------------------------------------------------------------
-- Friendships
-- ---------------------------------------------------------------------------
create table public.friendships (
  id uuid primary key default uuid_generate_v4(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending', -- pending | accepted | blocked
  created_at timestamptz not null default now(),
  unique (requester_id, addressee_id)
);

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------
create table public.groups (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member', -- owner | admin | member
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Trips
-- ---------------------------------------------------------------------------
create table public.trips (
  id uuid primary key default uuid_generate_v4(),
  group_id uuid references public.groups (id) on delete set null,
  created_by uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  status text not null default 'planned', -- planned | active | completed | cancelled
  origin_name text,
  origin_point geography(point, 4326),
  destination_name text,
  destination_point geography(point, 4326),
  scheduled_start timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  route_polyline text, -- encoded polyline for the planned route
  created_at timestamptz not null default now()
);

create table public.trip_members (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  invite_status text not null default 'invited', -- invited | accepted | declined
  joined_at timestamptz,
  primary key (trip_id, user_id)
);

-- Planned or ad-hoc stops along a trip (food, scenery, fuel, custom)
create table public.trip_stops (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  kind text not null default 'custom', -- food | scenery | fuel | rest | custom
  name text not null,
  point geography(point, 4326) not null,
  planned_arrival timestamptz,
  actual_arrival timestamptz,
  actual_departure timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Live location pings (high-frequency, short retention)
-- ---------------------------------------------------------------------------
create table public.location_pings (
  id bigint generated always as identity primary key,
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  point geography(point, 4326) not null,
  speed_mps real,
  heading real,
  recorded_at timestamptz not null default now()
);

create index location_pings_trip_time_idx on public.location_pings (trip_id, recorded_at desc);
create index location_pings_user_time_idx on public.location_pings (user_id, recorded_at desc);

-- ---------------------------------------------------------------------------
-- Trip stats summary (rollup, updated as the trip progresses)
-- ---------------------------------------------------------------------------
create table public.trip_stats (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  total_distance_km double precision not null default 0,
  max_speed_kmh double precision not null default 0,
  avg_speed_kmh double precision not null default 0,
  duration_seconds integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Fuel & expense logs
-- ---------------------------------------------------------------------------
create table public.trip_expenses (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  category text not null default 'fuel', -- fuel | food | toll | lodging | other
  amount numeric(10, 2) not null,
  currency text not null default 'USD',
  fuel_liters numeric(8, 2),
  odometer_km double precision,
  note text,
  logged_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Map images / sticky notes (photos pinned to a location)
-- ---------------------------------------------------------------------------
create table public.map_posts (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  point geography(point, 4326) not null,
  storage_path text not null, -- path in the "map-media" storage bucket
  caption text,
  visibility text not null default 'group', -- private | group | public
  created_at timestamptz not null default now()
);

create table public.map_post_shares (
  post_id uuid not null references public.map_posts (id) on delete cascade,
  shared_with_user uuid references public.profiles (id) on delete cascade,
  shared_with_group uuid references public.groups (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Chat (group + trip text channels)
-- ---------------------------------------------------------------------------
create table public.chat_messages (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid references public.trips (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text,
  attachment_path text,
  created_at timestamptz not null default now()
);

create index chat_messages_trip_idx on public.chat_messages (trip_id, created_at);
create index chat_messages_group_idx on public.chat_messages (group_id, created_at);

-- ---------------------------------------------------------------------------
-- AI planning assistant: conversations + remembered places/plans
-- ---------------------------------------------------------------------------
create table public.ai_conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text,
  created_at timestamptz not null default now()
);

create table public.ai_messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.ai_conversations (id) on delete cascade,
  role text not null, -- user | assistant
  content text not null,
  created_at timestamptz not null default now()
);

create table public.ai_saved_places (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  point geography(point, 4326),
  notes text,
  created_at timestamptz not null default now()
);

create table public.scheduled_trips (
  id uuid primary key default uuid_generate_v4(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  scheduled_for timestamptz not null,
  created_by_ai boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.trip_stops enable row level security;
alter table public.location_pings enable row level security;
alter table public.trip_stats enable row level security;
alter table public.trip_expenses enable row level security;
alter table public.map_posts enable row level security;
alter table public.map_post_shares enable row level security;
alter table public.chat_messages enable row level security;
alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
alter table public.ai_saved_places enable row level security;
alter table public.scheduled_trips enable row level security;

-- Profiles: anyone authenticated can read (needed for username/friend search);
-- only the owner can write.
create policy "profiles_select_all" on public.profiles
  for select using (auth.role() = 'authenticated');
create policy "profiles_insert_self" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles_update_self" on public.profiles
  for update using (auth.uid() = id);

-- Friendships: participants only.
create policy "friendships_select_participant" on public.friendships
  for select using (auth.uid() = requester_id or auth.uid() = addressee_id);
create policy "friendships_insert_requester" on public.friendships
  for insert with check (auth.uid() = requester_id);
create policy "friendships_update_participant" on public.friendships
  for update using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Groups & members: visible/writable to members only.
create policy "groups_select_member" on public.groups
  for select using (
    exists (select 1 from public.group_members m where m.group_id = id and m.user_id = auth.uid())
  );
create policy "groups_insert_owner" on public.groups
  for insert with check (auth.uid() = owner_id);
create policy "groups_update_owner" on public.groups
  for update using (auth.uid() = owner_id);

create policy "group_members_select_member" on public.group_members
  for select using (
    exists (select 1 from public.group_members m where m.group_id = group_members.group_id and m.user_id = auth.uid())
  );
create policy "group_members_insert_owner_or_self" on public.group_members
  for insert with check (
    auth.uid() = user_id
    or exists (select 1 from public.groups t where t.id = group_id and t.owner_id = auth.uid())
  );

-- Trips & members: visible to trip members only.
create policy "trips_select_member" on public.trips
  for select using (
    auth.uid() = created_by
    or exists (select 1 from public.trip_members jm where jm.trip_id = id and jm.user_id = auth.uid())
  );
create policy "trips_insert_creator" on public.trips
  for insert with check (auth.uid() = created_by);
create policy "trips_update_creator" on public.trips
  for update using (auth.uid() = created_by);

create policy "trip_members_select_member" on public.trip_members
  for select using (
    exists (select 1 from public.trip_members jm2 where jm2.trip_id = trip_members.trip_id and jm2.user_id = auth.uid())
  );
create policy "trip_members_insert_creator_or_self" on public.trip_members
  for insert with check (
    auth.uid() = user_id
    or exists (select 1 from public.trips j where j.id = trip_id and j.created_by = auth.uid())
  );
create policy "trip_members_update_self" on public.trip_members
  for update using (auth.uid() = user_id);

-- Trip-scoped tables: member-of-trip gate, reused via a helper predicate.
create policy "trip_stops_select_member" on public.trip_stops
  for select using (
    exists (select 1 from public.trip_members jm where jm.trip_id = trip_stops.trip_id and jm.user_id = auth.uid())
  );
create policy "trip_stops_write_member" on public.trip_stops
  for insert with check (
    exists (select 1 from public.trip_members jm where jm.trip_id = trip_stops.trip_id and jm.user_id = auth.uid())
  );

create policy "location_pings_select_member" on public.location_pings
  for select using (
    exists (select 1 from public.trip_members jm where jm.trip_id = location_pings.trip_id and jm.user_id = auth.uid())
  );
create policy "location_pings_insert_self" on public.location_pings
  for insert with check (auth.uid() = user_id);

create policy "trip_stats_select_member" on public.trip_stats
  for select using (
    exists (select 1 from public.trip_members jm where jm.trip_id = trip_stats.trip_id and jm.user_id = auth.uid())
  );
create policy "trip_stats_upsert_self" on public.trip_stats
  for insert with check (auth.uid() = user_id);
create policy "trip_stats_update_self" on public.trip_stats
  for update using (auth.uid() = user_id);

create policy "trip_expenses_select_member" on public.trip_expenses
  for select using (
    exists (select 1 from public.trip_members jm where jm.trip_id = trip_expenses.trip_id and jm.user_id = auth.uid())
  );
create policy "trip_expenses_insert_self" on public.trip_expenses
  for insert with check (auth.uid() = user_id);

-- Map posts: owner can always see/write; shared audience can read.
create policy "map_posts_select_owner_or_shared" on public.map_posts
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.map_post_shares s
      where s.post_id = map_posts.id
        and (
          s.shared_with_user = auth.uid()
          or exists (select 1 from public.group_members tm where tm.group_id = s.shared_with_group and tm.user_id = auth.uid())
        )
    )
  );
create policy "map_posts_insert_self" on public.map_posts
  for insert with check (auth.uid() = user_id);

create policy "map_post_shares_select_related" on public.map_post_shares
  for select using (
    shared_with_user = auth.uid()
    or exists (select 1 from public.map_posts p where p.id = post_id and p.user_id = auth.uid())
  );
create policy "map_post_shares_insert_post_owner" on public.map_post_shares
  for insert with check (
    exists (select 1 from public.map_posts p where p.id = post_id and p.user_id = auth.uid())
  );

-- Chat: trip/group members only.
create policy "chat_messages_select_member" on public.chat_messages
  for select using (
    (trip_id is not null and exists (select 1 from public.trip_members jm where jm.trip_id = chat_messages.trip_id and jm.user_id = auth.uid()))
    or (group_id is not null and exists (select 1 from public.group_members tm where tm.group_id = chat_messages.group_id and tm.user_id = auth.uid()))
  );
create policy "chat_messages_insert_sender" on public.chat_messages
  for insert with check (auth.uid() = sender_id);

-- AI assistant tables: owner only.
create policy "ai_conversations_owner" on public.ai_conversations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ai_messages_owner" on public.ai_messages
  for all using (
    exists (select 1 from public.ai_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.ai_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  );
create policy "ai_saved_places_owner" on public.ai_saved_places
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "scheduled_trips_select_member" on public.scheduled_trips
  for select using (
    exists (select 1 from public.trip_members jm where jm.trip_id = scheduled_trips.trip_id and jm.user_id = auth.uid())
  );
create policy "scheduled_trips_insert_member" on public.scheduled_trips
  for insert with check (
    exists (select 1 from public.trip_members jm where jm.trip_id = scheduled_trips.trip_id and jm.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- Storage buckets (run once; safe to re-run)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('map-media', 'map-media', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Realtime: broadcast changes needed for live sync
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['location_pings', 'chat_messages', 'trip_members', 'map_posts']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
