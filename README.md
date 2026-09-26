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
teammate's vehicle drawn as a bundled 3D model. What's left of the product
vision is tracked in "Roadmap" below.

## Stack

- **Flutter** (Dart 3.13 / Flutter 3.47) with **ForUI** widgets (`forui`) over a
  navigation-grade design system — see `core/theme/`
- **Supabase**: Postgres + PostGIS, Auth, Realtime, Storage
- **Riverpod** for state, **go_router** for navigation with auth-aware redirects
- **Multiavatar** (`multiavatar_plus` + `flutter_svg`) for generated avatars
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
    constants/    # env access, avatar (Multiavatar seed) / vehicle catalogs
    providers/    # app prefs (intro seen) + user settings
    router/       # go_router + auth-state redirect logic
    theme/        # nav palette tokens + ForUI theme (day/night)
  data/
    models/       # Profile, Group, Trip, TripStop, TripExpense, TripStats
    repositories/ # Supabase query wrappers per domain
    services/     # SupabaseService bootstrap
  features/
    welcome/      # pre-auth intro carousel
    auth/         # sign in / sign up
    onboarding/   # username + avatar + vehicle picker
    home/         # bottom-nav shell
    map/          # live 3D map + 3D vehicle models + navigate-to-friend sheet
      map_engine/ # Mapbox engine: map widget, 3D scene, vehicle models, markers
    trip/         # trip list, invites, new-trip flow, detail (stats/stops/expenses)
    social/       # friends (search/request/accept), groups, group detail
    chat/         # AI trip assistant + group text/voice chat (all live)
    voice/        # (empty — see roadmap)
    settings/     # preferences, account, privacy, data & about
    profile/      # profile screen (links into social/ and settings/)
supabase/
  migrations/0001_init.sql   # full schema + RLS + storage buckets + realtime
server/           # ranmap-server: Node/TS backend for secret-holding operations
  src/
    index.ts        # Express app entry
    routes/ai.ts     # POST /ai/conversations/:id/messages
    routes/account.ts        # POST /account/delete (deletes the auth user)
    routes/notifications.ts  # POST /notifications/register | /unregister
    lib/ai-tools.ts  # save_place / schedule_trip tool definitions + execution
    lib/push.ts      # FCM delivery (opt-out aware); no-op without credentials
    lib/supabase.ts  # secret-key Supabase client
    middleware/require-auth.ts  # verifies the forwarded Supabase JWT
```

## Setup

### 1. Supabase project

1. Create a project at https://supabase.com.
2. Run the migrations in order: `supabase/migrations/0001_init.sql`,
   `0002_rls_hardening.sql`, `0003_integrity_and_live_locations.sql`,
   `0004_stop_ordering.sql`, `0005_phone_verification.sql`,
   `0006_trip_route_planning.sql`, `0007_security_fixes.sql`,
   `0008_hardening_followups.sql`, `0009_plans.sql`, `0010_plan_limits.sql`,
   then `0011_notifications.sql` and `0012_text_length_limits.sql` (either paste
   them into the SQL editor in that order, or `supabase db push`). `0011`
   adds `device_tokens` (written only by ranmap-server; no client access) and
   `notification_prefs` (owner-managed) for push notifications. `0001`
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
   `0008` closes the remaining follow-ups: it adds an in-function caller check
   to `prune_location_pings`/`start_due_scheduled_trips` (defence in depth on
   top of the REVOKE), revokes the lingering PUBLIC EXECUTE on
   `create_trip`/`create_group`/`update_trip_route` (anon can no longer even
   invoke them), makes the service-role grants explicit, validates the CHECK
   constraints `0007` added as `NOT VALID`, and adds the indexes the scheduler
   and pruner hot paths were missing.
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

`BACKEND_URL` is where the app reaches **ranmap-server**. On a simulator/emulator
`localhost` is fine; on a **physical phone** `localhost` is the phone itself, so
either forward the port (`adb reverse tcp:8787 tcp:8787` on Android) or point it
at your Mac over Wi-Fi (`http://192.168.x.x:8787` or `http://your-mac.local:8787`).
Cleartext HTTP to that host is allowed only in debug builds (Android
`android/app/src/debug/res/xml/network_security_config.xml`, iOS
`NSAllowsLocalNetworking`); release builds should use an `https://` backend.

### 3. Mapbox (rendering + routing)

The map is rendered by the **Mapbox Maps SDK for Flutter**, but the app ships
**no long-lived Mapbox token**. At runtime it asks ranmap-server for a
short-lived **temporary** token (`GET /maps/token`): a leaked token expires
within the hour, and rotating the account's secret is a server-only change —
installed apps keep working, with no update required. So nothing
Mapbox-related goes in the app's `.env`.

- **Android** still needs a **secret** downloads token (`sk.…`, with the
  `DOWNLOADS:READ` scope) so Gradle can pull the SDK from Mapbox's Maven
  repository. Don't commit it — set `MAPBOX_DOWNLOADS_TOKEN` in
  `~/.gradle/gradle.properties` (or as an environment variable);
  `android/build.gradle.kts` reads it.
- The server holds the Mapbox credential(s): one token for Directions + Search
  Box, which ALSO mints the app's rendering tokens, so it needs `tokens:write`
  plus `styles:read`, `fonts:read`, and `styles:tiles` — set
  `MAPBOX_ACCESS_TOKEN` and your account's `MAPBOX_USERNAME` in `server/.env`.
  Google's Places API (New) is used for **one** thing only — the richer
  per-place metadata (rating, review count, opening hours) fetched when a user
  taps a single search result — and its key (`GOOGLE_MAPS_API_KEY`) also stays
  server-side.

### 4. ranmap-server (AI trip assistant + phone verification + voice)

The AI assistant, phone number verification, and voice channels all need
the backend running locally:

```
cd server
cp .env.example .env
```

Fill in `server/.env`:

Supabase and Anthropic are required — the server won't start without them.
Everything else is **optional**: leave it unset and the server still runs, with
only the routes that need it returning `503` (and a startup warning listing
what's missing). Uncomment + fill in what you have:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=sb_secret_your-key   # Project Settings → API Keys — server-only, never ship this
ANTHROPIC_API_KEY=your-anthropic-api-key
# ANTHROPIC_MODEL=claude-sonnet-4-5                 # optional override
# --- optional integrations ---
# GOOGLE_MAPS_API_KEY=your-google-maps-server-key   # Places API (New); per-place details only
# MAPBOX_ACCESS_TOKEN=sk.your-mapbox-secret-token   # SECRET (sk.), not pk.: mints the app's map token, so needs tokens:write + styles:read/fonts:read/styles:tiles
# MAPBOX_USERNAME=your-mapbox-username              # account the app's rendering tokens are minted under
# REVENUECAT_SECRET_KEY=sk_your_revenuecat_secret_key   # billing. Reads subscriber state
# REVENUECAT_WEBHOOK_AUTH=long-random-string            # matches the RevenueCat webhook's Authorization header
# TWILIO_ACCOUNT_SID=your-twilio-account-sid
# TWILIO_AUTH_TOKEN=your-twilio-auth-token
# TWILIO_VERIFY_SERVICE_SID=your-twilio-verify-service-sid   # Twilio Console → Verify → Services
# LIVEKIT_URL=wss://your-project.livekit.cloud               # LiveKit Cloud (or a self-hosted server)
# LIVEKIT_API_KEY=your-livekit-api-key
# LIVEKIT_API_SECRET=your-livekit-api-secret
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

### Plans (Ranmap Pro)

Paid features are gated **server-side** — the client's flags are UX only, so a
patched app can't bypass them. `profiles.plan` (see
`supabase/migrations/0009_plans.sql`) is written **only** by the billing webhook
using the secret key; clients can read their own plan via the `my_plan()` RPC
but have no UPDATE grant on it.

- **Gated, per user**: the AI assistant (`/ai/*`) and a daily cap on route &
  place search (`/maps/*`). Free accounts get a metered allowance first
  (`requireProOrTrial`), so the feature is discoverable before it's paywalled.
  The meter lives in Postgres (`consume_usage`), so it's shared across server
  instances.
- **Gated, travel together**: voice channels (`/voice/token`) are unlocked when
  **any** member of the trip/group is Pro, not just the caller — one subscriber
  covers the whole crew (`trip_has_pro` / `group_has_pro`).
- **Gated, hard caps** (`0010_plan_limits.sql`, enforced by DB triggers so a
  modified client can't bypass them): free accounts may keep **3** active trips,
  pin **25** photos, and groups are capped at **6** members. Raising a member to
  Pro lifts that group's cap for everyone.
- **Gated, display-only**: full trip stats & history.
- A gate returns **HTTP 402** with `{ code: "premium_required", feature }`, which
  the client turns into the Ranmap Pro paywall (`showPaywall`); DB cap triggers
  raise `Ranmap Pro required: …`, which the client maps to the same paywall.

Billing is wired through **RevenueCat** (which wraps StoreKit 2 / Play Billing):

- The client configures the RevenueCat SDK with a **public** key
  (`REVENUECAT_IOS_KEY` / `REVENUECAT_ANDROID_KEY` in the app `.env`), logs the
  user in with their Supabase id, and drives the paywall from the `pro`
  entitlement (`lib/features/premium/revenuecat.dart`).
- RevenueCat calls `POST /billing/revenuecat`; the server verifies the shared
  `Authorization` value (`REVENUECAT_WEBHOOK_AUTH`), re-reads the subscriber via
  the RevenueCat API with the secret key (`REVENUECAT_SECRET_KEY`), and writes
  `profiles.plan` — the only writer. So a leaked client key can't grant Pro, and
  the app never holds a secret.

To enable it: create the products in App Store Connect / Play Console, attach
them to a `pro` entitlement with current + default offerings in RevenueCat, set
the two public keys in `.env` and the two server keys in `server/.env`, and point
the RevenueCat webhook at `/billing/revenuecat`. With no keys set the app runs
normally and the paywall reports billing as unavailable.

### 5. Install & run

```
flutter pub get
flutter run
```

Location, microphone, and camera permission strings are already declared in
`Info.plist` (iOS/macOS) and `AndroidManifest.xml` (Android); the macOS
entitlements cover network, camera, audio input, and location.

### Release signing (Android)

`flutter run --release` works out of the box (it falls back to the debug
keys), but a real release must be signed with your own keystore. Copy
`android/key.properties.example` to `android/key.properties`, point
`storeFile` at your keystore, and fill in the passwords — `build.gradle.kts`
picks it up automatically (and both files are gitignored).

## What's already wired

- **Auth**: email/password sign up & sign in via Supabase Auth.
- **Onboarding**: a pre-auth intro carousel (`/welcome`, shown once), then a
  unique-username check, an avatar picker, and a vehicle type picker
  (car/bike/scooter/SUV) — writes to `profiles`.
- **Avatars**: either a **Multiavatar** — a random one is generated by default
  and the user can pick another or shuffle — stored as a *seed* in
  `avatar_id`; or an **uploaded photo**, stored in the public `avatars` bucket
  under `<uid>/…` and referenced as `custom:<path>` in the same column. Legacy
  values (`default`, the old animal ids) are still valid seeds, so no data
  migration is needed and no image is required unless the user uploads one.
- **Routing**: `go_router` redirects first-run signed-out users to `/welcome`,
  signed-out users to `/sign-in`, signed-in users without a profile to
  `/onboarding`, and everyone else to the home shell.
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
  alternate routes — tap a route's chip to select it,
  then "Use this route" saves it on the trip (`origin_*`/
  `destination_*`/`route_polyline`, via the extended `create_trip` RPC).
  The active trip's route renders as a polyline on the live map. A search
  FAB on the map opens `NearbyPlacesSheet`, which searches nearby
  food/fuel/lodging/sights around your current position and drops a marker on
  the one you pick. Tapping a result fetches its rating, review count, and
  opening hours.
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
  A **photo gallery** (`TripPhotosScreen`, opened from the trip's app bar)
  shows every photo on a trip as a grid instead of only as map pins.
- **Along-the-way places**: the map's nearby-places sheet has a "Search along
  the route" toggle when the active trip has a planned route — it hands the
  route polyline to the provider's native search-along-route search (one
  request covering the whole route), so you can find fuel/food *on the way*
  rather than only around your current position.
- **Next-stop ETA**: the Stops tab shows a banner for the next un-arrived
  stop with the distance from your live position and an ETA derived from the
  trip's average speed.
- **Fuel estimate**: the Stats tab derives a `$ / km` rate from the trip's
  fuel expenses and distance, and (when a route is planned) projects the
  estimated fuel cost for the whole route from its polyline.
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
  call five tools — `save_place` (writes to `ai_saved_places`),
  `create_trip` (creates a trip and enrolls the user as its first accepted
  member, optionally scheduling it in the same step), `schedule_trip`
  (looks up one of the user's existing trips by title and inserts into
  `scheduled_trips`), `invite_friend_to_trip` (looks up a user by exact
  username and adds them to a trip the caller is on), and `add_stop`
  (appends a located stop to one of the caller's trips). All tool inputs are
  validated server-side (latitude/longitude ranges, future-only schedule
  times, allowlisted stop kinds) and scoped to the authenticated user. The client only ever talks to the backend,
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
  delete one you created; remove a friend or cancel a request. **Delete
  account** (Settings → Account, double-confirmed) calls `POST /account/delete`
  on ranmap-server, which best-effort removes the user's storage files and then
  deletes the auth user — every row cascades from `auth.users → profiles`.
- **Push notifications (server-ready)**: `0011_notifications.sql` adds
  `device_tokens` (server-only) and owner-managed `notification_prefs`; the
  server registers tokens via `POST /notifications/register` and delivers
  through FCM (`lib/push.ts`, opt-out aware, dead tokens pruned) when
  `FIREBASE_SERVICE_ACCOUNT_JSON` is set — it sends on trip invitations today
  (via the AI assistant's `invite_friend_to_trip`), and reports `push: false`
  so the app can be honest when unconfigured. Settings → Notifications manages
  the opt-outs. **The Flutter client doesn't yet obtain an FCM token** (that
  needs `firebase_messaging` + your Firebase project); until it does, nothing
  is delivered. Chat-message pushes also need a DB webhook/trigger, since
  messages are written by the client, not the server.
- **Settings**: a `SettingsScreen` (gear in the Profile header) with
  Preferences (theme light/dark/system, distance units km/miles, default map
  style + 3D buildings + terrain — all persisted and applied to the live map),
  Account (edit profile incl. display name, change password, change email,
  sign out other devices), Privacy (default photo visibility, location-sharing
  note), Data (clear the offline write queue) and About (version, licenses).
- **Theming**: light and dark ForUI themes; the mode follows the system setting
  or the user's choice in Settings. Distance/speed readouts respect the unit
  preference.
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

## Tests & CI

- **Client**: `flutter test` runs the unit tests in `test/` — model
  parsing/round-trips, the offline outbox, polyline decoding, the trip-stats
  rollup, the map-engine helpers, and the geo distance helper.
- **Server**: `cd server && npm test` (Node's built-in test runner via
  `tsx`) covers the rate limiter's bucketing/`Retry-After` behaviour.
- **Database**: `supabase test db` runs the pgTAP suite in
  `supabase/tests/rls_test.sql` — RLS-enabled checks, the RPC EXECUTE grants,
  and behavioural checks that a non-member can't read or self-join a trip.
- **CI**: `.github/workflows/ci.yml` runs `flutter analyze` + `flutter test`
  and, for the server, `npm run typecheck` + `npm test` + `npm run build`.

## Roadmap (not yet built)

Each of these is a substantial feature; the schema and folder structure
already anticipate them:

- **Voice polish**: join/mute/leave + a live participant list is live (see
  above), and the client now auto-reconnects with exponential backoff if the
  connection drops. Still open: it's audio-only (no video), there's no
  push-to-talk/deafen, and it isn't "always-on" Discord-style — you join
  explicitly rather than the app auto-joining when a trip goes active.
- **Photo sharing polish**: capture/pin and the trip gallery/grid are live
  (see above). Still open: a UI for `map_post_shares` (sharing a specific
  photo with a friend or another group beyond its default trip-participant
  visibility).
- **AI trip assistant polish**: the chat UI, conversation history, and all
  five tools (`save_place`/`create_trip`/`schedule_trip`/
  `invite_friend_to_trip`/`add_stop`) are live (see above). Still open: the
  `ranmap-server` scheduler poller could move to a proper job queue or
  Supabase Edge Function on a cron trigger for production instead of an
  in-process `setTimeout` loop.
- **Route planning polish**: origin/destination are picked on the map
  rather than searched by name/address (no Places Autocomplete/geocoding
  yet), and a planned route isn't re-plannable once a trip is active —
  `update_trip_route` exists for this but no screen calls it yet.
- **Voice always-on**: joining is still explicit; an app-wide voice session
  that auto-joins when a trip goes active (Discord-style) isn't built.
