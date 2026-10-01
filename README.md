# Ranmap

**Google Maps is single-player. Ranmap makes the whole crew one map.**

Ranmap is a social road-trip app. Start a trip with your group and everyone
shows up live on one 3D map as their own vehicle — talking over push-to-talk
voice, planning shared stops, splitting expenses, and pinning photos to the
route, while an AI assistant plans the trip for you.

<p align="center">
  <img src="submission/app-icon-1024.png" width="144" alt="Ranmap app icon">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: AGPL-3.0-or-later" src="https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-Dart%203.13-02569B?logo=flutter&logoColor=white">
  <img alt="Supabase" src="https://img.shields.io/badge/backend-Supabase-3FCF8E?logo=supabase&logoColor=white">
  <img alt="RevenueCat" src="https://img.shields.io/badge/monetization-RevenueCat-F25A5A?logo=revenuecat&logoColor=white">
</p>

> **Shipaton 2026 — Next Gen Award entry.** Demo video: <!-- TODO: paste YouTube/Vimeo link --> · Devpost: <!-- TODO: paste Devpost submission link -->

## The idea

Navigation apps are built for one person: you type a destination, you drive, and
the people you're travelling *with* are invisible. Ranmap adds the missing
multiplayer layer. On a trip, every rider shows up on the same live map as their
own vehicle, and the whole convoy can talk, plan, and split the trip in one
place.

It's deliberately crew-first. Solo search and navigation exist only as the
on-ramp to a shared trip; the features that matter get better the more people
are on the trip — live positions, voice, shared stops, voting, a shared ledger.

## What's in the app

- **Live 3D convoy map** — Mapbox Standard's extruded buildings, terrain and
  time-of-day lighting, with each teammate drawn as a bundled 3D vehicle model
  (car / bike / scooter / SUV), rotated to their heading.
- **Live sync & tracking** — each device holds one websocket to ranmap-server
  and joins its trip's or group's room, which relays positions between members
  (`lib/live-rooms.ts`). The server verifies the token and membership at join and
  stamps the sender, so a member can't forge another's position, and presence is
  simply the connection — a member who drops is gone immediately. Positions are
  held in memory only, and keep updating while the app is backgrounded.
- **Voice and chat** — LiveKit voice rooms with push-to-talk and speaking
  indicators, plus realtime group text, per trip and per group.
- **Shared trip toolkit** — reorderable stops with next-stop ETAs, weather en
  route, expenses with fuel-cost estimates projected over the whole route, and a
  shared packing checklist.
- **AI trip assistant** — Gemini with Google Search grounding that can actually
  create trips, schedule them, invite friends, and save places through tools.
- **Group convoy** — a persistent crew screen independent of any trip, with SOS,
  "regroup here" with auto check-in, quick statuses, and an SMS fallback.
- **Offline-first** — a persisted write queue with idempotent replay, plus
  downloadable map tiles so the route works with no signal.
- **Phones, photos, documents** — Twilio Verify phone OTP, photos pinned to the
  route, and a private document wallet.

## Screenshots

<!-- TODO: drop the 1179x2556 screenshots into submission/ and uncomment.
<p align="center">
  <img src="submission/screenshot-map.png" width="240" alt="Live 3D convoy map">
  <img src="submission/screenshot-trip.png" width="240" alt="Trip detail">
  <img src="submission/screenshot-ai.png" width="240" alt="AI trip assistant">
</p>
-->

## Product focus

**Promise: ride together, stay in sync.** Ranmap is for people travelling as a
group: everyone on one live map, talking over voice, planning stops and sharing
the trip. That is what we sell, and what the app, the website and the store
listings lead with.

Solo features exist, but only as the on-ramp: search and navigation, recording
a ride, saved places, Home/Work. They give someone value on day one and a reason
to open the app before they have a crew. They are never the headline.

How to apply it when adding or changing something:

- **Copy leads with the crew.** Welcome, website hero, store text and empty
  states talk about riding together. A solo path is a quiet secondary line
  ("Just ride solo"), not a second pitch.
- **Primary action is crew-first.** "Plan a trip with your crew" is the main
  button; solo options sit below it.
- **Solo must never change what a crew trip does.** A trip with two or more
  people behaves exactly as designed, including voice and live location.
- **Prefer features that get better with more people** (shared stops, voting,
  live location, group chat, shared expenses) over features a single user could
  get from a general maps or fitness app.
- **Do not compete on generic navigation or fitness tracking.** Navigation and
  ride stats are there so a trip works end to end, not to out-feature Google
  Maps or Strava.

## Monetization

Ranmap is subscription-first, and the whole thing runs through **RevenueCat**.
Three tiers (`free` < `pro` < `extreme`) are sold as monthly / annual products
with a 7-day annual trial; the paywall (`lib/features/premium/`) reads real store
prices from the RevenueCat offering instead of hard-coding them.

**Plans** (the store prices are the source of truth; these are the recommended
list the marketing copy mirrors):

- **Free** — metered AI + search; up to **3** active trips, **25** photos, **1**
  document, **1** saved route, and groups capped at **6** members.
- **Pro — $4.99/mo / $39.99/yr** (7-day trial on annual) — **100** trips,
  **5,000** photos, **100** documents, **100** saved routes, **100** members, plus
  the full trip stats & history.
- **Extreme — $9.99/mo / $79.99/yr** — **250** trips, **20,000** photos, **500**
  documents, **500** saved routes, **250** members.

- **The client** configures the RevenueCat SDK with a *public* key, logs the user
  in with their Supabase id, and drives the paywall off the `pro` / `extreme`
  entitlements. It never holds a secret.
- **The server owns entitlement truth.** `POST /billing/revenuecat` verifies the
  webhook's shared secret, re-reads the customer through the RevenueCat **v2**
  REST API with the secret key, and writes `profiles.plan` — the only writer. A
  leaked client key can't grant Pro.
- **Enforcement is server- and database-side.** A paid gate returns HTTP 402
  (`premium_required`) → paywall; a paid tier's fair-use ceiling returns a plain
  429 (`limit_reached`). Hard caps (trips, photos, documents, group size) are
  enforced by DB triggers, so a patched client can't bypass them.
- **One subscription covers the whole crew.** Pro is evaluated per trip/group
  (`trip_has_pro` / `group_has_pro`), so a single subscriber unlocks voice and
  lifts the caps for everyone they travel with.
- **Metered, not unlimited.** The AI assistant (tokens / 30 days) and route &
  place search (per day) are metered with a visible allowance meter, so provider
  cost stays bounded on every tier.

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
  Gemini-backed AI trip assistant (with Google Search grounding), Twilio
  Verify-backed phone OTP, and
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
   `0011_notifications.sql`, `0012_text_length_limits.sql`,
   `0013_ai_message_tools.sql`, `0014_trip_schedule_autostart.sql`,
   `0015_stop_proposals.sql`, `0016_trip_legs.sql`,
   `0017_profile_search.sql`, `0018_service_role_rpc_user.sql`,
   `0019_trip_currency.sql`, `0020_usage_status.sql`,
   `0021_add_usage.sql`, `0022_realtime_trip_locations.sql`,
   `0023_broadcast_position.sql`, `0024_rate_limit_store.sql`,
   `0025_usage_rpc_state.sql`, `0026_group_roles_and_invites.sql`,
   `0027_group_convoy.sql`, `0028_trip_planning_and_statuses.sql`,
   `0029_trip_shares.sql`, `0030_service_and_documents.sql`,
   `0031_support_requests.sql`, `0032_plan_limits_documents_routes.sql`,
   `0033_pro_fair_use_limits.sql`,
   `0034_extreme_tier.sql`, `0035_audit_hardening.sql` and
   `0036_usage_reservations.sql` (either paste
   them into the SQL editor in that order, or `supabase db push`). `0036`
   splits the AI token meter's in-flight reservation out of settled usage
   (`usage_counters.reserved` plus a `settle_usage` RPC), so a running turn's
   hold no longer shows as usage in the quota meter; it replaces `add_usage`
   with reserve + settle. `0035`
   closes a batch of audit findings (storage-path repointing, PUBLIC execute on
   the entitlement predicates, and group-cap gaps). `0034`
   adds the Extreme tier (`plan` gains `'extreme'`; `is_pro` now means *paid* =
   pro OR extreme, plus `is_extreme`, `group_has_extreme`, and the `*_extreme`
   `plan_limit` keys); `0033`
   adds the Pro fair-use ceilings (`*_pro` keys) so Pro is capped rather than
   unlimited, and raises a distinct `Plan limit reached:` message for a Pro user
   (vs `Ranmap Pro required:` for a free one); `0032`
   extends `plan_limit` with `documents`/`route_templates` and adds the
   triggers capping a free account at one document and one saved route. `0025`
   makes `consume_usage` / `add_usage` return their resulting counter state, so
   the Redis cache can be refreshed in the same round-trip. `0024`
   moves rate-limit buckets into Postgres so they're shared across server
   instances. `0023`
   adds the `broadcast_position` RPC — the server stamps the sender id, so a
   client can't forge another member's live position. `0022`
   adds the Realtime Authorization policies that let only a trip's accepted
   members receive on the private live-position broadcast channel.
   `0021`
   adds `add_usage`, which records a variable number of units (AI tokens are
   only known after the model responds). `0020`
   adds the read-only `usage_status` RPC behind `GET /plan/usage`, so the app
   can show a quota meter before a free limit is hit. `0019`
   adds `trips.currency` and threads it through `create_trip`, so the ledger
   and fuel figures have one deliberate currency instead of one arbitrary
   expense row's. `0018`
   adds the `p_user` escape hatch to `create_trip`/`propose_stop` so the AI
   server's service-role client can act for a user (auth.uid() is NULL under
   that key), and makes `scheduled_trips` one schedule per trip. `0017`
   enables `pg_trgm` and adds the `search_profiles` RPC (typo-tolerant username
   search; the app falls back to a plain substring search if it's absent).
   `0011`
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

Supabase and Gemini are required — the server won't start without them.
Everything else is **optional**: leave it unset and the server still runs, with
only the routes that need it returning `503` (and a startup warning listing
what's missing). Uncomment + fill in what you have:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=sb_secret_your-key   # Project Settings → API Keys — server-only, never ship this
GEMINI_API_KEY=your-gemini-api-key
# GEMINI_MODEL=gemini-3.1-flash-lite                # optional override
# --- optional integrations ---
# REDIS_URL=redis://localhost:6379                  # optional; shares rate limits, allowances & auth caches across instances (falls back to Postgres when unset)
# GOOGLE_MAPS_API_KEY=your-google-maps-server-key   # Places API (New); per-place details only
# MAPBOX_ACCESS_TOKEN=sk.your-mapbox-secret-token   # SECRET (sk.), not pk.: mints the app's map token, so needs tokens:write + styles:read/fonts:read/styles:tiles
# MAPBOX_USERNAME=your-mapbox-username              # account the app's rendering tokens are minted under
# REVENUECAT_SECRET_KEY=sk_your_revenuecat_secret_key   # billing (V2 key). Reads customer state
# REVENUECAT_PROJECT_ID=proj_your_revenuecat_project_id # billing. Scopes the v2 REST API
# REVENUECAT_WEBHOOK_AUTH=long-random-string            # matches the RevenueCat webhook's Authorization header
# TWILIO_ACCOUNT_SID=your-twilio-account-sid
# TWILIO_AUTH_TOKEN=your-twilio-auth-token
# TWILIO_VERIFY_SERVICE_SID=your-twilio-verify-service-sid   # Twilio Console → Verify → Services
# LIVEKIT_URL=wss://your-project.livekit.cloud               # LiveKit Cloud (or a self-hosted server)
# LIVEKIT_API_KEY=your-livekit-api-key
# LIVEKIT_API_SECRET=your-livekit-api-secret
# FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}   # push delivery (FCM); whole service-account JSON on one line
# CORS_ORIGIN=https://app.example.com             # optional; only needed for Flutter web
```

```
npm install
npm run dev
```

This starts the backend on `http://localhost:8787` (matching `BACKEND_URL`
above). It verifies the Supabase session token the app forwards, then: for
the AI assistant, calls Gemini (with Google Search grounding) and our tools
for saving places, creating trips, scheduling them, inviting friends, and
adding/proposing stops, executing those tool calls with the secret key;
for phone verification, calls Twilio Verify to send/check
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
  place search (`/maps/*`). Free accounts get a metered allowance first, so the
  feature is discoverable before it's paywalled. The meter lives in Postgres
  (`consume_usage` / `usage_status` / `reserve_usage` / `release_usage` /
  `settle_usage`), so it's shared across server instances. Two shapes: **search**
  counts requests (`requireProOrTrial` consumes one up front); the **AI
  assistant** is metered in **tokens** — the cost is only known after the model
  responds, so `requireWithinAllowance` checks the cap up front, the route holds
  an upper-bound reservation while the model runs, then `settleUsage` records the
  real spend and releases the hold. The hold is tracked separately
  (`usage_counters.reserved`), so it never shows up as usage. `GET /plan/usage`
  reports both, and the app renders a
  **free-plan usage meter** on the Profile tab. Paid tiers are **metered too**,
  against a larger fair-use ceiling (`proMax` for Pro, `extremeMax` for Extreme
  — 5M / 15M AI tokens per 30 days, 2,000 / 5,000 searches per day), so provider
  spend stays bounded even for subscribers; a paid user who hits their tier's
  ceiling gets a plain **HTTP 429 `limit_reached`**, never an upgrade paywall.
- **Shared state, not per-process**: rate-limit buckets, the metered
  allowances, and the plan/membership lookups are served from **Redis** when
  `REDIS_URL` is set, so several `ranmap-server` instances don't multiply a
  limit or hammer Postgres on every request. Each falls back to Postgres
  (correct, just slower) when Redis is absent or erroring:
  - *Rate limits* — Redis `INCR` + TTL, else `consume_rate_limit` (0024), else
    the in-memory store (single instance/tests). Fail **open** if every store
    fails, logged loudly.
  - *Allowances* — Postgres stays the **source of truth**
    (`consume_usage` / `usage_status` / `reserve_usage` / `release_usage` /
    `settle_usage`); Redis is a
    **read-through cache** in front of it, refreshed on a miss and after every
    write. A flush or eviction costs one extra Postgres read — it can never hand
    back a fresh allowance, because the durable counter is never bypassed. (The
    writes stay in Postgres deliberately: billing-adjacent data, low volume, and
    a durable counter is worth one round-trip.)
  - *Plan & membership* — cached booleans with a short TTL (60s) in front of
    `is_pro` / `trip_has_pro` / `group_has_pro` / `is_trip_participant` /
    `is_group_member`; the billing webhook invalidates the caller's own plan
    entry so a purchase takes effect immediately rather than waiting out the
    TTL.
- **Gated, travel together**: voice channels (`/voice/token`) are unlocked when
  **any** member of the trip/group is Pro, not just the caller — one subscriber
  covers the whole crew (`trip_has_pro` / `group_has_pro`).
- **Tiers** (ordered `free` < `pro` < `extreme`; `profiles.plan`):
  `is_pro` means **paid** (pro OR extreme), so Extreme inherits every Pro gate;
  `is_extreme` marks the top tier. One paid member still unlocks the whole
  trip/group.
- **Gated, hard caps** (`0010_plan_limits.sql` + `0032`/`0033`/`0034`, enforced
  by DB triggers so a modified client can't bypass them). Free: **3** active
  trips, **25** photos, **1** document, **1** saved route, groups capped at **6**.
  Pro raises these to **100** trips, **5,000** photos, **100** documents, **100**
  saved routes and **100** members; Extreme to **250**, **20,000**, **500**,
  **500** and **250** respectively. Generous ceilings, not literally unlimited
  (`0033_pro_fair_use_limits.sql`, `0034_extreme_tier.sql`). Raising one group
  member to a paid tier lifts that group's cap for everyone.
- **Gated, display-only**: full trip stats & history.
- A gate returns **HTTP 402** with `{ code: "premium_required", feature }`, which
  the client turns into the Ranmap Pro paywall (`showPaywall`); a paid tier's
  ceiling returns **HTTP 429** with `{ code: "limit_reached", feature }` (a plain
  error, not a paywall); DB cap triggers raise `Ranmap Pro required: …` for a free
  user (mapped to the paywall) or `Plan limit reached: …` for a Pro/Extreme user.

Billing is wired through **RevenueCat** (which wraps StoreKit 2 / Play Billing):

- The client configures the RevenueCat SDK with a **public** key
  (`REVENUECAT_IOS_KEY` / `REVENUECAT_ANDROID_KEY` in the app `.env`), logs the
  user in with their Supabase id, and drives the paywall from the `pro`
  entitlement (`lib/features/premium/revenuecat.dart`).
- RevenueCat calls `POST /billing/revenuecat`; the server verifies the shared
  `Authorization` value (`REVENUECAT_WEBHOOK_AUTH`), re-reads the customer via
  the RevenueCat **v2** API with the secret key (`REVENUECAT_SECRET_KEY`) and
  project id (`REVENUECAT_PROJECT_ID`), and writes `profiles.plan` — the only
  writer. So a leaked client key can't grant Pro, and the app never holds a
  secret.

To enable it: create the products in App Store Connect / Play Console, attach
them to a `pro` entitlement with current + default offerings in RevenueCat, set
the two public keys in `.env` and the three server values in `server/.env`, and
point the RevenueCat webhook at `/billing/revenuecat`. With no keys set the app runs
normally and the paywall reports billing as unavailable.

Recommended products (the paywall reads real store prices, so these are the
source of truth for what users see — the marketing copy mirrors them):
**Pro** `pro_monthly` **$4.99 / month** and `pro_annual` **$39.99 / year**;
**Extreme** `extreme_monthly` **$9.99 / month** and `extreme_annual`
**$79.99 / year**. Attach Pro to the `pro` entitlement and Extreme to the
`extreme` entitlement, with a **7-day free trial** on the annual products. The
client resolves packages by identifier (`pro_annual`, `extreme_monthly`, …).
Anything shown for "free" on the paywall is derived from `plan_limit()` and the
metered allowances in `server/src/lib/allowances.ts`, not hard-coded.

### 5. Firebase (push notifications — optional)

Push is optional: without it the app runs normally and Settings → Notifications
shows "Push unavailable". To enable delivery:

1. Create a Firebase project at https://console.firebase.google.com.
2. **Android** — add an app with package `com.ranmap.app`, drop the downloaded
   `google-services.json` into `android/app/`, and apply the Google Services
   Gradle plugin (`com.google.gms.google-services`) in
   `android/settings.gradle.kts` and `android/app/build.gradle.kts`.
   (`minSdk` is already 23 for `firebase_messaging`.)
3. **iOS** — add an app with bundle id `com.ranmap.app`, drop
   `GoogleService-Info.plist` into `ios/Runner/`, then in Xcode enable the
   **Push Notifications** capability and **Background Modes → Remote
   notifications** for the Runner target. Upload your APNs key under Firebase →
   Project settings → Cloud Messaging.
4. **Server** — set `FIREBASE_SERVICE_ACCOUNT_JSON` in `server/.env` (the whole
   service-account JSON on one line).
5. Run the app and tap **Settings → Notifications → Turn on notifications**.
   That asks for the OS permission and registers the device's FCM token; a trip
   invite then delivers a push. The token is refreshed on rotation and on
   sign-in, and forgotten on sign-out.

### 6. Install & run

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
- **Live sync**: while a trip is active, your GPS fixes are published to a
  **private, per-trip Realtime broadcast channel** (`tripLiveSyncProvider`),
  and every teammate's position renders as a live 3D vehicle model on the map
  as it arrives — with no database write per fix. Publishing goes through the
  `broadcast_position` RPC, so the **server stamps the sender id** (a client
  can't forge another member's position). The `trip_member_locations` RPC is
  still fetched on every (re)subscribe as the authoritative cold-start/reconcile
  path, so a missed broadcast (offline, reconnect) heals on the next snapshot.
  A much coarser `location_pings` trail (≈ every 45s) is persisted for
  stats/history, cutting rows ~50–100×. Tracking continues while the app is
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
  It runs on **Gemini 3.1 Flash-Lite** via the Interactions API with **Google
  Search grounding** (so it can answer current-information questions) plus our
  function tools. Messages are stored in `ai_conversations`/`ai_messages`; the assistant can
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
- **Push notifications**: `0011_notifications.sql` adds `device_tokens`
  (server-only) and owner-managed `notification_prefs`. The app registers its
  FCM token via `POST /notifications/register`
  (`lib/core/push/push_service.dart`, `firebase_messaging`); it asks for the OS
  permission only when the user taps Settings → Notifications → "Turn on
  notifications", refreshes on token rotation and sign-in, and forgets the token
  on sign-out. The server delivers through FCM (`lib/push.ts`, opt-out aware,
  dead tokens pruned) when `FIREBASE_SERVICE_ACCOUNT_JSON` is set, and reports
  `push: false` so the app can be honest when unconfigured. It sends on trip
  invitations — from the app's own invite path (`POST /notifications/trip-invite`,
  creator-scoped) and from the AI assistant's `invite_friend_to_trip`. See
  "Firebase" in Setup. Chat-message pushes are sent by the client after a
  message is posted — `POST /notifications/chat-message` (member-scoped) from
  `lib/features/chat/chat_screen.dart` and `chat_share.dart`; no DB trigger is
  needed because the client is the sender.
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

## Recently built / roadmap

Built since this section was a plain "not yet built" list:

- **Voice** — a **deafen** toggle (mutes all incoming audio by unsubscribing
  every remote audio publication) and **video** (camera publish +
  `VideoTrackRenderer` tiles in a participant grid), alongside mute and
  push-to-talk. A denied mic/camera now shows an **Open Settings** hint with a
  retry (`core/permissions/app_permission_hint.dart`) instead of a dead end.
- **Photo sharing** — the viewer lists **who a photo is shared with** and can
  **remove a share** (owner-only), revoking that recipient's access.
- **Scheduled trips** — the in-process `setTimeout` poller is gone. **pg_cron**
  starts due trips (`start_due_scheduled_trips()`, migration `0049`); a trigger
  on `trips.status → 'active'` enqueues a durable **`push_jobs`** outbox row;
  the server drains it (retryable). This also notifies on a *manual* start, and
  a crash can no longer drop the "trip started" push.
- **Route planning** — origin/destination **and** the nearby-POI free-text
  search are now session-based **autocomplete**: Mapbox Search Box `/suggest`
  (unmetered) + `/retrieve` (one search unit), with a client-generated session
  id.

Still open:

- **Voice video** — the tile layout is a fixed two-column grid (tap a tile for
  full-screen). Screen sharing is intentionally out of scope for the product.

## License

Copyright (C) 2026 Harmanpreet Singh.

Ranmap is free software, licensed under the **GNU Affero General Public
License, version 3 or later** (AGPL-3.0-or-later). See [LICENSE](LICENSE) for
the full text.

The AGPL's network clause (section 13) matters here: anyone who runs a
modified version of `ranmap-server` or `web-app` as a network service must
offer that service's users the corresponding source.
