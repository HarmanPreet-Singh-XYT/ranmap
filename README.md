# Ranmap

Travel together, stay in sync. Start a trip with your group, watch each
other move live on the map, talk over voice, and keep a shared log of the
trip — stats, fuel, expenses, stops, and photos pinned to the route.

This repo currently contains the **foundational skeleton, live sync, social
graph, trip logging, a stats dashboard, group text + voice chat, photo
sharing, phone verification, route planning, and an AI trip assistant**:
project architecture, Supabase schema, auth, onboarding (username + avatar +
vehicle), friends/groups, starting/inviting to a trip with invite
accept/decline, live teammate tracking with navigate-to-friend and
per-vehicle-type 3D models, per-trip stops (map-picked or current-location,
reorderable, with planned-arrival ETAs) + expense logging with totals, a
live-updating distance/speed/duration dashboard with fuel cost averages,
real-time group text chat plus a LiveKit voice channel per trip/group,
capturing and pinning photos to the route, Twilio Verify-backed phone
number OTP, alternate-route planning + nearby-places search via the
Directions/Places APIs, and a chat-based AI assistant that can save places,
create trips, and schedule them. The map is a real 3D layer — Mapbox
Standard's extruded buildings, trees, landmarks, and terrain, with each
teammate's vehicle drawn as a bundled 3D model. The rest of the product
vision is stubbed with `TODO`s at the right seams — see "Roadmap" below.

## Stack

- **Flutter** (Dart 3.13 / Flutter 3.47), Material 3
- **Supabase**: Postgres + PostGIS, Auth, Realtime, Storage
- **Riverpod** for state, **go_router** for navigation with auth-aware redirects
- **mapbox_maps_flutter** (Maps SDK v11) for the 3D map — extruded buildings,
  terrain, and glTF vehicle models — plus **geolocator** for positioning
- **url_launcher** to hand off turn-by-turn navigation to the native Maps app
- **image_picker** for capturing/picking photos pinned to the map
- **livekit_client** for voice channels (audio over WebRTC via a LiveKit room)
- **ranmap-server** (`server/`, Node + TypeScript + Express): a small
  backend for anything that needs a secret key server-side — the
  Anthropic-backed AI trip assistant, Twilio Verify-backed phone OTP, and
  minting LiveKit voice-room tokens. The client never holds an LLM, Twilio,
  or LiveKit key; it forwards its Supabase session token to the backend,
  which verifies it and performs privileged operations (writes with the
  Supabase secret key, or minting a scoped LiveKit token) on its
  behalf. Future secret-holding features belong here too.

## Project layout

```
lib/
  app/            # RanmapApp root widget
  core/
    constants/    # env access, avatar/vehicle catalogs
    router/       # go_router + auth-state redirect logic
    theme/        # AppTheme
  data/
    models/       # Profile, Group, Trip, TripStop, TripExpense, TripStats
    repositories/ # Supabase query wrappers per domain
    services/     # SupabaseService bootstrap
  features/
    auth/         # sign in / sign up
    onboarding/   # username + avatar + vehicle picker
    home/         # bottom-nav shell
    map/          # live 3D map + 3D vehicle models + navigate-to-friend sheet
      map_engine/ # Mapbox engine: map widget, 3D scene, vehicle models, markers
    trip/         # trip list, invites, new-trip flow, detail (stats/stops/expenses)
    social/       # friends (search/request/accept), groups, group detail
    chat/         # AI trip assistant + group text/voice chat (all live)
    voice/        # (empty — see roadmap)
    profile/      # profile screen (links into social/)
supabase/
  migrations/0001_init.sql   # full schema + RLS + storage buckets + realtime
server/           # ranmap-server: Node/TS backend for secret-holding operations
  src/
    index.ts        # Express app entry
    routes/ai.ts     # POST /ai/conversations/:id/messages
    lib/ai-tools.ts  # save_place / schedule_trip tool definitions + execution
    lib/supabase.ts  # secret-key Supabase client
    middleware/require-auth.ts  # verifies the forwarded Supabase JWT
```

## Setup

### 1. Supabase project

1. Create a project at https://supabase.com.
2. Run the migrations in order: `supabase/migrations/0001_init.sql`,
   `0002_rls_hardening.sql`, `0003_integrity_and_live_locations.sql`,
   `0004_stop_ordering.sql`, `0005_phone_verification.sql`,
   `0006_trip_route_planning.sql`, then `0007_security_fixes.sql` (either paste
   them into the SQL editor in that order, or `supabase db push`). `0001`
   creates all tables (profiles,
   groups, trips, stops, expenses, location pings, map posts, chat, AI
   assistant tables), enables PostGIS, sets up the base Row Level Security
   policies, creates the `avatars` and `map-media` storage buckets, and adds
   the realtime tables needed for live sync. `0002` tightens RLS (blocks
   self-joining trips/groups, gates trip/group writes on membership, hides
   `phone_number`/`socials`), adds the missing DELETE and storage policies,
   and honours `map_posts.visibility`. `0003` adds the friendship-pair
   unique index, atomic `create_trip`/`create_group` RPCs, the
   `trip_member_locations` RPC used by the live map, and a ping-retention
   job. `0004` adds manual stop ordering (`trip_stops.sort_order`,
   backfilled from existing data) and an atomic `reorder_trip_stops` RPC.
   `0005` adds `profiles.phone_verified` (writable only by the service
   role — see step 4), auto-reset to false whenever a client changes
   `phone_number`. `0006` extends `create_trip` to optionally take an
   origin/destination/route in the same atomic call, and adds
   `update_trip_route` for setting/changing a trip's route afterwards. `0007`
   closes follow-up holes — it forces `chat_messages` to target exactly one
   channel, narrows the `profiles` INSERT grant so `phone_verified` can't be
   forged, stops a stop's `trip_id` being reassigned, validates the group in
   `create_trip`, guards `update_trip_route` against NULL coordinates, checks
   `map_posts.storage_path` ownership, adds enum/numeric CHECK constraints,
   revokes helper-function EXECUTE from `PUBLIC`, adds missing FK/GiST indexes,
   and makes the scheduler start step atomic. All migrations are idempotent.
3. Copy your project URL and **publishable key** from Project Settings →
   API Keys. (The new-style keys are `sb_publishable_…` / `sb_secret_…`;
   they replace the legacy anon / service-role keys.)

### 2. Environment variables

```
cp .env.example .env
```

Fill in:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_your-key
BACKEND_URL=http://localhost:8787
```

### 3. Mapbox token (native config)

The map is rendered by the **Mapbox Maps SDK for Flutter**. It needs a Mapbox
**public** access token (`pk.…`) — create one at
<https://console.mapbox.com/account/access-tokens/> and add it to `.env`:

```
MAPBOX_ACCESS_TOKEN=pk.your-mapbox-public-token
```

- **Android** additionally needs a **secret** downloads token (`sk.…`, with the
  `DOWNLOADS:READ` scope) so Gradle can pull the SDK from Mapbox's Maven
  repository. Don't commit it — set `MAPBOX_DOWNLOADS_TOKEN` in
  `~/.gradle/gradle.properties` (or as an environment variable);
  `android/build.gradle.kts` reads it.
- Route planning and nearby-places search still call the **Directions API** and
  **Places API** through ranmap-server (`GET /maps/directions`,
  `GET /maps/places/nearby`), which holds a server-side `GOOGLE_MAPS_API_KEY`.
  That key never ships in the client.

### 4. ranmap-server (AI trip assistant + phone verification + voice)

The AI assistant, phone number verification, and voice channels all need
the backend running locally:

```
cd server
cp .env.example .env
```

Fill in `server/.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=sb_secret_your-key   # Project Settings → API Keys — server-only, never ship this
ANTHROPIC_API_KEY=your-anthropic-api-key
# ANTHROPIC_MODEL=claude-sonnet-4-5                 # optional override
GOOGLE_MAPS_API_KEY=your-google-maps-server-key   # Directions/Places web-service key, restrict by server IP
TWILIO_ACCOUNT_SID=your-twilio-account-sid
TWILIO_AUTH_TOKEN=your-twilio-auth-token
TWILIO_VERIFY_SERVICE_SID=your-twilio-verify-service-sid   # Twilio Console → Verify → Services
LIVEKIT_URL=wss://your-project.livekit.cloud               # LiveKit Cloud (or a self-hosted server)
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
# CORS_ORIGIN=https://app.example.com             # optional; only needed for Flutter web
```

```
npm install
npm run dev
```

This starts the backend on `http://localhost:8787` (matching `BACKEND_URL`
above). It verifies the Supabase session token the app forwards, then: for
the AI assistant, calls Claude with tools for saving places, creating
trips, and scheduling them, executing those tool calls with the
secret key; for phone verification, calls Twilio Verify to send/check
a code and, on success, writes `phone_number`/`phone_verified` to the
caller's own profile with the secret key; for voice, checks the
caller is actually a trip participant / group member (via the same SQL
predicates RLS uses) and mints a short-lived LiveKit room token.

### 5. Install & run

```
flutter pub get
flutter run
```

Location, microphone, and camera permission strings are already declared in
`Info.plist` (iOS) and `AndroidManifest.xml` (Android).

## What's already wired

- **Auth**: email/password sign up & sign in via Supabase Auth.
- **Onboarding**: unique username check, cartoony avatar picker, vehicle
  type picker (car/bike/scooter/SUV) — writes to `profiles`.
- **Routing**: `go_router` redirects signed-out users to `/sign-in`,
  signed-in users without a profile to `/onboarding`, and everyone else to
  the home shell.
- **Friends & groups**: search by username, send/accept/decline friend
  requests (`FriendsScreen`), create groups and add friends as members
  (`GroupsScreen`/`GroupDetailScreen`) — wraps `friendships`/`groups`/
  `group_members` via `FriendRepository`/`GroupRepository`.
- **Trips**: create a trip, optionally plan a route, invite group members
  (by username or picked from friends), start it — `TripListScreen` +
  `NewTripScreen` wired to `TripRepository`. Invitees see a pending-invite
  card on the trip list with accept/decline before the trip shows up as
  theirs.
- **Route planning & nearby places**: `PlanRouteScreen` (from "Plan route"
  in New Trip) lets you pick an origin and destination and fetches
  alternate routes from the Directions API — tap a route's chip to select it,
  then "Use this route" saves it on the trip (`origin_*`/
  `destination_*`/`route_polyline`, via the extended `create_trip` RPC).
  The active trip's route renders as a polyline on the live map. A search
  FAB on the map opens `NearbyPlacesSheet`, which queries the Places API for
  nearby food/fuel/lodging/sights around your current position and drops a
  marker on the one you pick.
- **Live sync**: while a trip is active, your own GPS position streams to
  `location_pings` (`locationBroadcastProvider`), and every other member's
  latest position renders as a live 3D vehicle model on the map via the
  `trip_member_locations` RPC refreshed on Supabase Realtime
  (`tripMemberLocationsProvider`). Tracking continues while the app is
  backgrounded (Android foreground service / iOS background location).
- **Navigate to friend**: tapping the status card lists the live teammates;
  choosing one shows distance + compass direction and can hand off to the
  native Maps app for turn-by-turn directions to their live location. (The
  vehicles are 3D style layers, and Mapbox Standard doesn't support
  `queryRenderedFeatures`, so the list is the tap target rather than the
  model itself.)
- **3D vehicle models**: each live vehicle — yours (via the 3D location puck)
  and every teammate's — is a bundled glTF model for their `vehicle_type`
  (car/bike/scooter/SUV), rotated to their heading and depth-integrated with
  the 3D buildings. The models are generated, low-poly, real-world-scale
  boxes (`assets/models/*.glb`, built by
  `tool/generate_vehicle_models.py`) since the repo bundles no binary art.
  The map also has a 3D toggle for Mapbox Standard's extruded
  buildings/trees/landmarks, a terrain toggle, and a basemap cycle
  (Standard / Satellite / Outdoors) with time-of-day lighting. Photo and place
  pins are drawn procedurally by `MapMarkers`.
- **Group chat & voice**: Chat & Voice → Group Chat lists a channel per trip
  you're on and per group you're in (`ChatChannelsScreen`); opening one
  (`ChatScreen`) shows a live-updating thread over `chat_messages`, kept in
  sync via Supabase Realtime. Long-press your own message to delete it. The
  call icon in the app bar opens `VoiceChannelScreen`, which fetches a
  LiveKit room token from `ranmap-server` (`POST /voice/token`, membership
  checked server-side) and joins a voice room named after that same
  channel — mute toggle, leave, and a live participant list with
  speaking/muted indicators.
- **Photo sharing**: on the map, the camera FAB (visible during an active
  trip) opens `AddMapPostScreen` to capture or pick a photo, caption it, and
  pin it at your current location. Photos upload to the private `map-media`
  bucket and appear as yellow pins for every trip participant
  (`map_posts`, RLS-scoped via `can_view_map_post`); tapping one opens a
  viewer sheet with a signed URL, and the poster can delete their own photo.
- **Trip stops & expenses**: `TripDetailScreen` (opened by tapping a trip)
  has a Stops tab and an Expenses tab (log fuel/food/toll/lodging/other with
  optional fuel-liters/odometer, running total + per-category breakdown) —
  wraps `trip_stops`/`trip_expenses` via `TripRepository`. Adding a stop
  (`AddStopScreen`) defaults its pin to your current location or lets you
  drag-pick any point on the map (`PickLocationScreen`), with an optional
  planned-arrival date/time. Stops append to the end of the trip's order and
  can be drag-reordered on the Stops tab (`ReorderableListView`, persisted
  atomically via the `reorder_trip_stops` RPC).
- **Stats dashboard**: a Stats tab on `TripDetailScreen` shows total
  distance, max/avg speed, duration, and average fuel cost. While a trip is
  active, `TripRepository.recomputeStats` re-derives these from your own
  `location_pings` (haversine distance between consecutive points, speed
  from each ping) every 10 pings and upserts `trip_stats`; completing a trip
  (via the app bar action) forces one final recompute so the dashboard
  reflects the whole ride.
- **AI trip assistant**: a chat tab (Chat & Voice → AI Assistant) backed by
  `ranmap-server`, with a conversation list screen (`AiConversationsScreen`)
  to browse, resume, or delete past conversations, or start a new one.
  Messages are stored in `ai_conversations`/`ai_messages`; the assistant can
  call three tools — `save_place` (writes to `ai_saved_places`),
  `create_trip` (creates a trip and enrolls the user as its first accepted
  member, optionally scheduling it in the same step), and `schedule_trip`
  (looks up one of the user's existing trips by title and inserts into
  `scheduled_trips`). The client only ever talks to the backend,
  authenticated via the forwarded Supabase session token — no LLM key on the
  client. A poller in `ranmap-server` (`lib/scheduler.ts`, every 60s) checks
  `scheduled_trips` for entries whose time has arrived and flips the trip to
  `active`.
- **Data layer**: `ProfileRepository`, `TripRepository`, `GroupRepository`,
  `AiRepository` wrapping typed Supabase queries (create trip, invite
  member, log location ping, add stop, log expense, stream live pings via
  Realtime, send an AI assistant message).
- **Profile & socials**: edit your username/avatar/vehicle after onboarding
  (`EditProfileScreen`), and link socials + a verified phone number
  (`LinkedSocialsScreen`); the private fields are read through the
  `my_private_profile` RPC since they aren't exposed to other users.
- **Phone verification**: entering a number and tapping "Send verification
  code" sends an OTP via Twilio Verify (through `ranmap-server`); entering
  the code calls `/phone/check-code`, which verifies it with Twilio and only
  then writes `phone_number`/`phone_verified=true` to the profile with the
  secret key — the client can never set `phone_verified` itself
  (revoked at the database grant level), and a verified number is
  automatically un-verified if the client edits `phone_number` directly
  (`0005_phone_verification.sql`).
- **Trip history**: `TripHistoryScreen` sums distance/time across your trips
  and lists each trip's rollup.
- **Delete / leave**: swipe a stop or expense to delete it; leave a trip or
  delete one you created; remove a friend or cancel a request.
- **Theming**: light and dark themes following the system setting.
- **Offline handling**: an app-wide banner reflects connectivity, and writes
  made while offline (chat messages, expenses, stops) are queued in a persisted
  outbox (`lib/core/offline/`) and replayed idempotently on reconnect. Screens
  show a retry affordance on load errors. (Reads still require a connection —
  there's no local replica of server data yet.)
- **Schema**: trips, trip members/invites, trip stops (food /
  scenery / fuel / rest / custom), location pings, per-trip stats rollup,
  fuel/expense logs, map photo posts with per-user/per-group sharing, group +
  friendship graph, chat messages, and AI assistant conversations/saved
  places/scheduled trips — all RLS-scoped to participants.

## Roadmap (not yet built)

Each of these is a substantial feature; the schema and folder structure
already anticipate them:

- **Voice polish**: join/mute/leave + a live participant list is live (see
  above), and the client now auto-reconnects with exponential backoff if the
  connection drops. Still open: it's audio-only (no video), there's no
  push-to-talk/deafen, and it isn't "always-on" Discord-style — you join
  explicitly rather than the app auto-joining when a trip goes active.
- **Photo sharing polish**: capture/pin is live (see above). Still open: a UI
  for `map_post_shares` (sharing a specific photo with a friend or another
  group beyond its default trip-participant visibility), and a gallery/grid
  view of a trip's photos instead of only pins on the map.
- **AI trip assistant polish**: the chat UI, conversation history, and
  `save_place`/`create_trip`/`schedule_trip` tools are all live (see above).
  Still open: more tools (e.g. inviting friends to a trip, adding a stop),
  and the `ranmap-server` scheduler poller could move to a proper job queue
  or Supabase Edge Function on a cron trigger for production instead of an
  in-process `setInterval`.
- **Route planning polish**: origin/destination are picked on the map
  rather than searched by name/address (no Places Autocomplete/geocoding
  yet), and a planned route isn't re-plannable once a trip is active —
  `update_trip_route` exists for this but no screen calls it yet. Nearby
  places also aren't tied to the route itself (e.g. "along the way"), only
  to a single point.
