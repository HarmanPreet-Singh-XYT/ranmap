## Inspiration

Navigation and fitness apps are built for one person. You type a destination,
you drive, and the people you're travelling *with* effectively disappear — they
become a text thread, a phone call, and a "where are you?" at the next fuel
stop. Group travel is one of the most social things we do, yet the software
treats it as a solo activity.

Ranmap started from a simple, familiar frustration: on a group road trip, nobody
actually knows where anyone is. Someone drops behind, someone misses the turn,
someone's low on fuel, and the real plan lives in five separate heads. We wanted
the map itself to be shared — one screen where the whole crew is visible, moving,
and reachable at once. Not a location tracker bolted onto a maps app, but a map
that assumes you're riding together.

That one idea — **ride together, stay in sync** — became the lens for every
decision after it. Solo features (search, navigation, saved places) exist only
as the on-ramp to a shared trip, never as the headline.

## What it does

Ranmap puts your entire road-trip crew on one live 3D map, and gives the group
everything it needs to move as a unit.

- **Live 3D convoy** — every teammate appears on the map as their own vehicle
  (car, bike, scooter or SUV), rendered as a real 3D model on Mapbox Standard's
  extruded buildings, terrain and time-of-day lighting. Positions update live,
  and keep updating while the app is backgrounded.
- **Push-to-talk voice and realtime chat** — a LiveKit audio room per trip and
  per group, with a walkie-talkie push-to-talk mode, speaking indicators and
  auto-reconnect, alongside live group text.
- **Shared trip toolkit** — reorderable stops with a next-stop ETA banner,
  weather at each planned arrival, an expense ledger with a fuel-cost estimate
  projected over the whole route, and a shared packing checklist.
- **AI trip assistant** — a chat assistant (Gemini with Google Search grounding)
  that doesn't just answer questions: it *acts*. It can create a trip, schedule
  it, invite a friend, save a place, or add and propose stops through real
  function tools.
- **Group convoy** — a persistent crew screen that works independently of any
  trip, with SOS to the whole group, "regroup here" with automatic check-in at a
  meeting point, and quick statuses like "Wait up" and "Need fuel".
- **A link anyone can follow** — the trip creator can mint a public, read-only
  page that family at home can watch with no account and no app.
- **Offline-first** — writes made without signal queue in a persisted outbox and
  replay idempotently; map tiles for a route can be downloaded for use with no
  connection at all.

## Monetization

Ranmap is subscription-first, built end to end on **RevenueCat**, with three
tiers and a generous free on-ramp so the app is useful before anyone pays.

- **Free** — full solo navigation plus the core crew features, with metered AI
  and search, capped at **3** active trips, **25** pinned photos and **6** group
  members.
- **Pro — $4.99/mo or $39.99/yr** — raises the caps (~100 trips, 5,000 photos,
  100 members), unlocks the full trip stats and history, and a much larger AI and
  search allowance.
- **Extreme — $9.99/mo or $79.99/yr** — the same features with the highest
  ceilings (~250 trips, 20,000 photos, 250 members).
- Both paid tiers include a **7-day free trial on the annual plans**, and the
  paywall reads live store prices from the RevenueCat offering rather than
  hard-coding them.

Two things make the monetization fit the product instead of fighting it. First,
**one subscription covers the whole crew**: because Pro is evaluated per trip and
per group, a single subscriber unlocks voice and lifts the caps for everyone they
travel with — so paying benefits your friends, who then want it too. Second, the
gates are real: entitlement truth is written only by our server from the
RevenueCat v2 API, and the hard caps are enforced by database triggers, so a
patched client can't unlock anything. A free user hitting a limit gets a
contextual paywall; a paid user hitting a fair-use ceiling gets a plain error,
never an upsell.

## How we built it

- **Client** — Flutter (Dart 3.13) with Riverpod for state, `go_router` for
  auth-aware navigation, and ForUI over a custom navigation-grade design system.
- **Map** — the Mapbox Maps SDK for Flutter (v11). The app ships no long-lived
  Mapbox token; it asks our backend for a short-lived rendering token at runtime.
- **Backend data** — Supabase (Postgres + PostGIS, Auth, Realtime, Storage). All
  rows are scoped with Row Level Security.
- **`ranmap-server`** — a small Node + TypeScript + Express backend that holds
  every secret the client must never have: it mints Mapbox and LiveKit tokens,
  runs the Gemini assistant, verifies phone numbers with Twilio, and validates
  RevenueCat webhooks. The client forwards its Supabase session token; the
  server verifies it before doing any privileged work.
- **Live sync** — positions travel over a private, per-trip Supabase Realtime
  broadcast channel, written through a database RPC that stamps the sender's id.
- **Billing** — the RevenueCat SDK on the client (public key only), with
  entitlement truth written server-side from the RevenueCat v2 REST API.
- **Voice** — LiveKit rooms, joined with a short-lived token minted by the server
  only after it confirms the caller is actually in that trip or group.

## Challenges we ran into

- **Trust in a live location feed.** A member must never be able to spoof another
  member's position. We publish through a database RPC that stamps the sender id
  server-side and revoke direct client inserts on the channel, so a modified app
  can't forge a teammate.
- **Making live positions cheap.** Writing a row per GPS fix doesn't scale. Live
  movement rides an ephemeral broadcast, and only a coarse trail is persisted —
  cutting database rows by roughly 50–100×.
- **Healing a fire-and-forget feed.** Broadcasts can be missed (offline,
  reconnect). Every (re)subscribe also fetches an authoritative snapshot, so a
  dropped message self-corrects instead of leaving a stale dot on the map.
- **Enforcing monetization honestly.** Client-side flags can be patched, so paid
  gates live in the backend and the hard caps (trips, photos, documents, group
  size) are enforced by database triggers. `profiles.plan` has exactly one
  writer — the webhook.
- **Bounding provider cost.** AI is metered in tokens, which are only known
  *after* the model responds. We hold an upper-bound reservation while a turn
  runs, then settle the real spend and release the hold, so a running request
  never shows up as usage in the user's meter.
- **Shipping 3D with no art budget.** The repo bundles no binary artwork, so the
  per-vehicle models are low-poly glTF boxes generated by a small Python tool at
  build time.
- **Background location on both platforms** — an Android foreground service and
  iOS background location, each with their own constraints and disclosures.

## Accomplishments that we're proud of

- A genuinely **end-to-end working app**: auth, onboarding, friends and groups,
  trips, live sync, chat and voice, photos, planning and an AI assistant all
  working together on real devices.
- **Live sync architecture** we'd defend in production: server-attested
  positions, an ephemeral broadcast for movement, and a snapshot that reconciles.
- **Monetization done properly.** RevenueCat is integrated the way it should be —
  real store prices on the paywall, entitlement truth owned by the server, and
  enforcement that a patched client can't bypass.
- **An AI assistant that takes action**, with every tool input validated
  server-side and scoped to the authenticated user.
- **A crew-first product**, where "one subscription covers the whole crew" isn't
  a marketing line but a property of the data model.
- **Tests and CI** across the client (`flutter test`), the server (Node test
  runner) and the database (pgTAP RLS suite).

## What we learned

- **The database is the real enforcement layer.** Row Level Security plus
  triggers are what make "you can't bypass this" true; client checks are UX.
- **Ephemeral-first, snapshot-second** is a strong pattern for live data: push
  fast and cheap, but always keep an authoritative reconcile path.
- **Metering needs reservations.** For anything priced after the fact, hold a
  bound up front and settle the truth afterwards.
- **Design principles beat feature lists.** Committing to "the crew comes first"
  made hundreds of small decisions obvious — what to build, what to cut, and what
  the empty states should say.

## What's next for Ranmap — One Map for the Whole Crew

- **Voice polish** — video and deafen on top of the existing app-wide voice
  session, mini-bar and push-to-talk.
- **Push notifications, fully wired** — the server side and preferences exist;
  the remaining piece is a database webhook/trigger so chat and alerts deliver
  reliably to every device.
- **Route planning polish** — session-based place autocomplete instead of
  debounced geocoding.
- **A proper job queue** for the scheduled-trip poller in production, instead of
  an in-process loop.
- **Store release** — the app is MVP-ready and being prepared for the App Store
  and Google Play, with a growth plan around the crew-first viral loop: every
  trip a user starts invites more of their friends into the same live map.

## Built With

**Client**

- Flutter, Dart
- Riverpod
- go_router
- ForUI

**Backend & data**

- Supabase — Postgres, PostGIS, Auth, Realtime, Storage, Row Level Security
- Node.js, TypeScript, Express
- Redis
- Docker

**Maps, media & realtime**

- Mapbox Maps SDK (Maps SDK v11)
- LiveKit
- Mapbox Directions, Geocoding & Search Box
- Google Places API
- Open-Meteo

**AI**

- Google Gemini
- Google Search grounding

**Capabilities & monetization**

- RevenueCat
- Twilio Verify
- Firebase Cloud Messaging
- Python (glTF vehicle-model generation)

<!-- Flat tag list for the Devpost "Built With" field (23 of 25):
Flutter, Dart, Riverpod, go_router, ForUI, Supabase, PostgreSQL, PostGIS, Node.js, TypeScript, Express, Redis, Docker, Mapbox, LiveKit, Google Places API, Open-Meteo, Google Gemini, Google Search grounding, RevenueCat, Twilio Verify, Firebase Cloud Messaging, Python
-->

