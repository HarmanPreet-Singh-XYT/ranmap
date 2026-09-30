# Ranmap Web — Frontend Plan

A standalone Next.js application, separate repo from this one, so its deploy
cadence never collides with `server/` or the Flutter app release cycle. It
shares the same Supabase project (auth + data) as the mobile app.

## Long-term vision (for context, not phase 1)

The web app eventually becomes a full planning companion to the mobile app:
same trips, groups, chat, AI assistant, and places search — everything except
the live convoy view (3D vehicle tracking, real-time GPS, LiveKit voice),
which is inherently mobile-only. Web is "plan and coordinate," mobile is
"drive together." See "Later phases" at the bottom for that scope.

**This document's real purpose is the phase 1 build below.** Everything after
"Later phases" is intentionally light — direction, not a spec — so phase 1
doesn't get gold-plated for features that are months out.

---

## Phase 1 (build this first)

Scope: marketing site + policies + support + full account management,
**including buying/managing a subscription from the web**. No trip planning,
no chat, no AI assistant yet — those are phase 2+.

### 1. Marketing

- `/` — landing page: hero, feature highlights, screenshots/demo, download
  CTAs (App Store / Play). This is the one area that uses ThreeUI (see
  below) for visual polish.
- `/features` — expands on hero sections from the app (live map, AI
  assistant, groups, expenses) — content-only, no functionality.
- `/pricing` — Free vs Pro comparison. Pricing copy should match whatever
  plan the RevenueCat products define (check current entitlement names/
  prices before writing copy, don't hardcode from memory).
- `/about` (optional, low priority)

### 2. Legal / policies

- `/privacy`
- `/terms`
- `/refund-policy` (relevant once web billing exists — see §4)
- Plain MDX or markdown-driven content, no CMS needed for this volume.

### 3. Support

- `/support` — contact form + FAQ. Start simple: a form that emails support
  or writes to a Supabase table for manual triage. A full ticketing system
  is not phase-1 scope.
- Decide before building: third-party widget (Crisp/Plain) vs. plain
  contact form. A widget is less code but adds a third-party script to
  every page; a form is fully owned but has no user-facing ticket status.
  **Open decision — pick before implementing.**

### 4. Account management (the meaty part of phase 1)

Authenticated area, Supabase Auth (same user pool as the mobile app — a user
who signs up on web can log into the app with the same credentials and vice
versa).

- `/login`, `/signup`, `/forgot-password` — Supabase Auth flows.
- `/account` — profile (name, avatar, email), change password, delete
  account. Mirrors `lib/features/profile/profile_screen.dart` and the
  server's `account.ts` delete-account behavior (best-effort storage
  cleanup before auth user removal).
- `/account/stats` — read-only dashboard: trips taken, distance traveled,
  groups joined. Pulled directly from Supabase tables the app already
  writes to (no new backend work needed for read-only queries, subject to
  existing RLS).
- `/account/billing` — **subscription management from the web.** This is
  the one piece that needs new backend work — see below.

#### Billing: the actual gap to solve

Current state: `profiles.plan` is written **only** by the RevenueCat webhook
(`server/src/routes/billing.ts`), which reacts to **mobile store purchases**
(App Store / Play Billing via RevenueCat). There is no web checkout path
today — no Stripe, no RevenueCat Web Billing integration.

**Decision: RevenueCat Web Billing.** Not a separate Stripe integration —
web purchases go through RevenueCat (Stripe under the hood on their side),
landing in the same subscriber record the mobile app already produces. This
reuses the existing entitlement model, webhook infra, and `plan_source`
tracking instead of standing up a second, independent source of truth for
"is this user Pro."

What that means concretely for the existing server code:

- `server/src/routes/billing.ts`'s webhook handler stays the single writer
  of `profiles.plan` — no change to that flow's shape.
- `planSourceFromStore` (`server/src/lib/revenuecat.ts`) needs a new case
  for the web billing store value RevenueCat sends (check their current
  docs for the exact string — this evolves, don't hardcode from memory)
  alongside the existing `app_store`/`play_store` handling.
- The Next.js app needs the RevenueCat Web Billing SDK/checkout flow
  (client-side) to initiate purchases, plus the user's RevenueCat App User
  ID kept in lockstep with their Supabase auth ID — mirroring the identity
  sync `main.dart` already does for mobile, so a web purchase and an app
  purchase both resolve to the same subscriber.

`/account/billing` needs:
- Current plan + status (active/expired/canceling) + renewal date.
- Upgrade/downgrade or cancel flow (RevenueCat customer portal, if using
  RevenueCat Web Billing, can often be embedded/linked rather than
  custom-built).
- Payment method management — deferred to whichever billing provider's
  hosted portal, not custom-built.

**Build status:** done. `/account/billing` reads the real `my_plan()` RPC and
shows Free/Pro/Extreme + expiry. Checkout uses the RevenueCat Web SDK
(`@revenuecat/purchases-js`) — `Purchases.configure({ apiKey, appUserId })`
with the App User ID set to the Supabase user id, then
`Purchases.getSharedInstance().purchase({ rcPackage })` against the current
offering's package (`app/(account)/_components/upgrade-button.tsx`). The key
and package id come from `NEXT_PUBLIC_REVENUECAT_WEB_BILLING_KEY` /
`NEXT_PUBLIC_REVENUECAT_PRO_PACKAGE_ID`; if the key is unset the button degrades
to a "subscribe in the app" message instead of failing. Purchases surface
through the same webhook, and `planSourceFromStore` now maps the `RC_BILLING`
store to a `web` plan_source. Remaining work to go fully live: fill in the two
env vars from the RevenueCat dashboard (Web Billing public key + the Pro
package identifier) and confirm the `store` value RevenueCat sends once a real
sandbox purchase is made.

### Design system for phase 1

Port the Flutter brand tokens to web design tokens rather than inventing a
new palette:

- Colors: `lib/core/theme/brand_palette.dart` — "Convoy Clean Modern" light
  (green primary `#006E2F`/`#22C55E`, warm neutrals) and a pine-tinted dark
  mode (never pure black, canvas `#0F1512`). Port both as CSS variables /
  Tailwind theme extension, with the same light/dark pairing.
- Shape language: pill-shaped radii (`BrandRadii` — 8/16/24/32/48/999px),
  diffuse ambient shadows (no heavy strokes), 8px spacing baseline
  (`BrandSpace`).
- Typography: Plus Jakarta Sans (already used app-wide).

One shared shell across the whole site: same nav, footer, and design tokens
on marketing, legal, support, and account pages. Nav swaps its links based
on auth state (logged out: Features/Pricing/Support/Sign in; logged in:
Account/Stats/Billing + avatar menu) but the chrome itself doesn't change.
Account pages use a plainer content layout inside that same shell — cards/
tables, no heavy motion — since dashboard density and 3D visuals don't mix.

### Stack

- Next.js (App Router), TypeScript.
- Supabase JS client for auth + data (talk to Supabase directly, not
  through `server/` — keeps the Express server mobile-API-only and avoids
  adding web-specific auth handling there).
- Tailwind + shadcn/ui for account/dashboard UI (forms, tables, cards).
- ThreeUI (see below) scoped only to marketing routes.
- MDX for policy/support content.

### ThreeUI usage (marketing only)

[ThreeUI](https://threeui.com) — open-source three.js component library,
free/Community tier: 50 parent components, 141 free variants, 23 singletons,
MIT licensed. Free tier has all controls/variants, just fewer components
than Pro.

Use it **only** inside a `(marketing)` route group:
- Hero background: a WebGL/shader scene or animated background behind the
  landing page headline.
- Section transitions: motion design components between feature blocks on
  scroll.
- Primary CTA button: one shader/liquid-metal button treatment for the main
  download CTA — sparingly, not on every button.

Do **not** use it on `/account/*`, `/support`, or `/privacy` /`/terms` —
those need to be fast, legible, and content-first. Mixing 3D backgrounds
into data tables or legal text actively hurts usability there.

```
git clone https://github.com/MengTo/threeui   # reference/local dev copy
npm install && npm run dev
```
Pro tier requires browser auth + `threeui-cli`; not needed for phase 1.

---

## Current structure (implemented)

The site is split into four clearly separated surfaces, so the product features no
longer live under `/account`:

- **Public** — `/`, `/features`, `/pricing`, `/routes`, `/privacy`, `/terms`,
  `/refund-policy`, `/support` (unchanged).
- **Auth + account** — `/login`, `/signup`, `/forgot-password`, `/reset-password`
  alongside `/account` (profile, stats, billing). Auth pages sit with the account area
  on purpose: both are the identity surface, and they share `_components/` + `actions.ts`.
- **App features** — everything under **`/app/*`**, in its own shell (desktop sidebar +
  mobile bottom tab bar; no marketing chrome). Auth-guarded by `app/app/layout.tsx`.
  - `/app/trips`, `/app/trips/new`, `/app/trips/[id]` (+ `stops`/`crew`/`expenses`/`checklist`)
  - `/app/groups`, `/app/groups/[id]`, `/app/groups/join/[code]`
  - `/app/friends`
  - `/app/chat` (Direct · Groups · AI), `/app/chat/direct/[id]`,
    `/app/chat/groups/[id]`, `/app/chat/ai`, `/app/chat/ai/[id]`
  - `/app/photos` (moved from `/account/photos`)
- **Backend bridge** — `/api/ranmap/[...path]` proxies to `RANMAP_SERVER_URL` with the
  caller's Supabase bearer token, so browser code never needs CORS on the Node server.

The AI chat is built on [prompt-kit](https://www.prompt-kit.com) components
(`components/ui/{prompt-input,message,markdown,chat-container,loader,prompt-suggestion,tool,system-message}.tsx`),
installed via the shadcn registry and running on the app's existing `@base-ui/react`
primitives.

---

## Later phases (direction only, not a spec)

Once phase 1 ships, the natural next additions, in roughly this order:

**Phase 2 — Trip planning core**
- `/app/trips`, `/app/trips/[id]` — trip list/detail, itinerary, stops,
  expense ledger. No live map tab.
- `/app/groups` — crew management, mirrors `groups_screen.dart` /
  `group_detail_screen.dart`.
- Invite flow — web needs its own accept-invite page since the app's deep
  links won't fire in a browser context.

**Phase 3 — Chat + AI assistant**
- `/app/trips/[id]/chat` — group chat over the same Supabase Realtime
  channel/table the app uses, so messages sent from web appear instantly
  in-app and vice versa.
- AI planning assistant — built with a prompt/chat UI kit (e.g. the Vercel
  AI SDK's chat components) talking to the existing `server/src/routes/
  ai.ts` + `ai-tools.ts` endpoint, which is already framework-agnostic.
  Same trial limits apply (15 messages / 30-day window for free users).
- Places search — wraps the existing Mapbox Search Box integration
  (`server/src/routes/maps.ts`) for POI lookup, no live tracking.

**Explicitly out of scope for web, indefinitely:**
- Live 3D convoy map / vehicle tracking (needs live GPS).
- Voice channels (LiveKit) — audio-only convoy feature, mobile-only.

The web app becomes "the full product minus the live map screen," which
means phase 3's `(app)` route group deserves an app-shell layout (sidebar/
workspace nav) rather than the marketing-page layout — but that's a phase 3
decision, not a phase 1 concern.

---

## Open decisions to settle before/while building phase 1

1. Support: third-party widget vs. plain contact form.
2. Repo name/location for the new Next.js project (separate repo, per
   earlier discussion).

Billing is decided: RevenueCat Web Billing (see §4 above) — not an open
question, just needs confirming against RevenueCat's current product/
pricing setup before implementation.
