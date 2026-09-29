# Ranmap — Full Feature Catalog

Ranmap is a social road-trip app: create a trip, invite your group, watch
everyone move live on a 3D map, talk over voice or text, log stops and
expenses, pin photos to the route, and lean on an AI assistant to plan it
all. This document catalogs **every** feature currently implemented in the
Flutter client and `ranmap-server` backend, with concrete examples pulled
directly from the code (real limits, real copy, real field names).

---

## 1. Onboarding & First Launch

### Feature tour
- First-launch screen (`/tour`), shown once, gated by `AppPrefs.featureTourSeen`.
- Runs *before* the welcome screen on a fresh install.

### Welcome screen (`/welcome`, shown once)
- 2×2 "bento" collage: 2 photo tiles + 2 pastel illustration tiles ("Convoy" car icon, "Live Audio" cell-tower icon), animated fade/scale-in.
- Headline "Drive Together, Stay Connected" with tag "Real-Time Convoy Navigation".
- Primary CTA "Get Started" → sign-up.
- "Continue with Google" / "Continue with Apple" buttons open the provider's OAuth screen (`signInWithProvider`) and complete the round-trip back into the app.
- Footer "Already have a RanMap account? Log in" → sign-in.
- 3-dot progress indicator showing position in the pre-auth flow.

---

## 2. Authentication

### Sign in
- Email + password fields with autofill hints, show/hide password eye toggle.
- Email validated via regex (`^[^\s@]+@[^\s@]+\.[^\s@]+$`); empty password rejected with "Enter your password".
- **"Forgot password?"**: requires a valid-looking email first, then calls Supabase `resetPasswordForEmail` and shows **"If an account exists for `<email>`, a reset link is on its way."** — deliberately doesn't confirm whether the account exists.
- Keyboard "done" submits the form.
- On success, no explicit navigation — the router's auth-state listener redirects automatically.

### Sign up
- Full Name (≤60 chars), Email, Password fields.
- **Live password-strength chips**: "8+ chars" and "At least 1 number" turn green as you type — both required to submit. Also capped at 72 characters (Supabase/bcrypt truncation limit).
- If email confirmation is required, shows **"If `<email>` is a new address, check your inbox to confirm it, then sign in."** instead of leaving the user stuck.
- Google/Apple buttons start the same OAuth flow as Welcome.

### Change credentials (Settings → Account)
- Password change: at least 8 characters and at most 72, must match confirmation ("Passwords do not match").
- Email change: validated with the shared `emailError` check; success shows **"Check your inbox to confirm the new email address."** (requires confirmation).
- "Sign out other devices" — confirmation dialog, calls `signOut(scope: others)`, toast "Signed out of other devices."

---

## 3. Profile Onboarding (Step 2 of 3 — `/onboarding`)

### Username ("Pilot Handle")
- 3–24 characters, pattern `^[a-zA-Z0-9_]+$` (letters/digits/underscore only) — e.g. rejects `ab` (too short) or `john doe` (space not allowed).
- Input formatter blocks disallowed characters as you type; max length enforced live.
- **Live availability check**: debounced 450ms after typing stops — spinner, then green "Available" or red "Taken" chip. A sequence counter discards stale results if you keep typing.
- Server-side re-check at submit time (race-safe against two devices claiming the same name).

### Avatar picker
- Defaults to a random **Multiavatar** identicon (deterministic SVG from a string seed — ~12.2 billion unique combinations).
- 5 candidate avatars shown with decorative labels: "Scout", "Navigator", "Cruiser", "Roamer", "Voyager" — plus a 6th "Custom" upload slot.
- "Shuffle" rerolls all 5 candidates.
- Custom photo upload: camera or gallery, compressed to `85%` quality / max `1024×1024`, uploaded to the public `avatars` bucket, stored as `custom:<path>` in the `avatar_id` column.
- Switching back to a generated avatar deletes any pending custom upload (best-effort).

### Vehicle picker
- 4 options in a 2×2 grid: Car ("Sport Coupe"), Bike ("Adventure Bike"), Scooter ("City Scooter"), SUV ("Electric SUV") — each with a decorative subtitle like "Agile • Lead Scout".
- Selected card gets a highlight + checkmark.

### Skip flow
- Header "Skip" button auto-generates a fallback handle `rider_<6 random hex chars>` (retries up to 5× if taken), keeps the already-shown random avatar + default vehicle ("car"), and creates the profile immediately.

---

## 4. Phone Verification (`/verify-phone`, Step 3 of 3, and reachable later from Linked Socials)

- Phone entry validated as E.164 international format (`^\+[1-9]\d{6,14}$`) — e.g. `+15551234567`; error "Enter your number in international format, e.g. +15551234567".
- "Send code" starts a 45-second resend countdown and autofocuses the code field.
- **OTP entry**: 6 custom-styled digit boxes overlaid on one invisible autofill-enabled field so SMS-autofill/paste works — active cell shows a blinking cursor, filled cells show the digit.
- "Edit" lets you change the number mid-flow (resets the countdown).
- After the countdown hits 0: a "Resend SMS" link appears.
- Code validated as exactly the configured length (`kOtpLength`, 6 by default — keep in sync with the Twilio Verify service setting).
- On success: **"Phone number verified"** toast, verified badge appears, navigates home.
- **Server side** (Twilio Verify, via `ranmap-server`):
  - Rate-limited **5 codes/hour per account AND 5 codes/hour per target phone number** — the latter specifically to stop SMS-bombing someone else's number.
  - Code-check rate-limited **10 attempts/15 min per account AND per number** (anti-brute-force).
  - On successful verification, checks the number isn't already linked to *another* account (409 "That number is already linked to another account").
  - `phone_verified` is writable only by the server's secret key — the client can never set it directly, and editing `phone_number` client-side auto-resets `phone_verified` to false.

---

## 5. Avatars (system-wide)

- **Multiavatar identicons**: any string seed deterministically maps to a unique generated avatar; SVG markup is cached per-seed to avoid regenerating on every rebuild.
- **Custom photo avatars**: stored as `custom:<storage-path>`; broken/missing photo falls back to a generic person icon instead of a broken image.
- Selected-state styling: 3px accent ring + glow vs. a plain 1.5px border for unselected options.
- `avatarSeedCandidates()` always includes the currently-selected seed so the picker never shows a "hole" where the active choice should be.

---

## 6. Profile & Settings

### Profile screen
- Avatar, display name (or just `@username` if none set), vehicle label (e.g. "Vehicle: Car").
- Tiles: **Friends** (badge = incoming request count), **Groups**, **Linked socials**, **Trip stats & history**, **Service & maintenance** (badge "Due" when a service is overdue), **Documents**.
- **Ranmap Pro tile**: "Active — thanks for the support" (green) if subscribed, else "Unlock AI, voice & more search" (amber) — tapping opens the paywall.
- **Sign out** with confirmation dialog.

### Service & maintenance
- Odometer is the **sum of recorded trip distance** — no manual mileage entry.
- Set a service interval (5,000–30,000 km presets); the screen shows distance since the last service, distance remaining, a progress bar, and a "Service due / Overdue by N" state.
- **"Mark as serviced"** records the current odometer as the last service. The Profile menu shows a "Due" badge when overdue.

### Documents
- A private wallet for **licence, insurance, registration, tickets** — stored in a private storage bucket (`documents`) that only the owner can read.
- Add a document by naming it, choosing its type, and picking an image; tap to open it (short-lived signed URL); delete removes both the row and the file.

### Edit profile
- Username (same validation as onboarding, only re-checks availability if actually changed).
- Display name — optional, ≤60 chars, helper text "Optional — shown where there's room, beside your @username."
- Avatar editor (upload/change/shuffle/revert-to-generated) and vehicle radio picker, same as onboarding.

### Linked socials
- **Phone number** section: green "Verified" badge shown only while the field still matches the stored verified number — editing it immediately un-badges it.
- **Instagram / X / TikTok** handle fields, each capped at 60 characters (`instagram.com/…`, `x.com/…`, `tiktok.com/@…`).
- Save only writes non-empty entries.

### Trip history (**Ranmap Pro–gated**)
- Non-Pro: paywall prompt — "Trip stats & history are a Ranmap Pro feature. Unlock your full distance, speed and duration history across every trip."
- Pro: summary card (trip count, total distance, total time) + per-trip rollup tiles.
- Duration formatted as `"{h}h {m}m"` or just `"{m}m"` under an hour.
- Empty state: "No trip stats yet. Each finished trip adds its distance, top speed and time to your history here." + "Plan a trip" → NewTripScreen.

### Settings screen
- **Preferences**: theme (System/Light/Dark), distance units (km/mi), map style, 3D buildings toggle, terrain toggle — all persisted and live-applied to the map.
- **Notifications**: four independent toggles — Trip invites, Chat messages, Group invites, Trip updates — each PATCHed to the server on change, optimistic with rollback-on-failure. Footer note: "Push delivery turns on once this build registers a device token with the server" (push isn't fully wired client-side yet).
- **Account**: Edit profile, Change password/email, "Sign out other devices".
- **Delete account** (double-confirmed): first dialog "Delete your account? This permanently deletes your profile, trips, photos, chats and messages. It cannot be undone." → second "Are you absolutely sure? There is no way to recover your data after this." → calls the server, which best-effort deletes storage files then the auth user (everything else cascades via FK).
- **Privacy**: default photo visibility (Only me / Trip members / Public); static note explaining location sharing stops when a trip ends or you leave it.
- **Safety**: an **Emergency contact** (name + phone, stored on-device only) used by the convoy's "Text emergency contact" SOS fallback.
- **Data**: "Clear offline queue" — shows live pending-write count, confirms, then wipes the outbox.
- **About**: version/build number, open-source licenses page.

---

## 7. Trips

### Trip list
- Two sections: pending **Invites** (accept/decline, only shown if non-empty) and **Your trips**.
- Each trip card shows a status badge (Planned / Active now / Completed / Cancelled) with a context action — "Start" for planned trips, a nav icon for active ones.
- Empty state: "No trips yet.\nStart one to invite your group and hit the road."
- Pull-to-refresh.

### New trip
- Name required, ≤60 chars.
- **"Plan route"** card (optional) — opens route planning; shows "No route planned" / "Route planned" state. A **"Saved"** button beside it fills the route from one of your saved route templates.
- Invite members by typed username (chip on submit) or "From friends" picker sheet; duplicate usernames silently ignored.
- On create: creates the trip, then invites each username — unresolvable usernames are reported after the fact via **"Trip created. Could not find: name1, name2"** without blocking creation.
- Hitting the free-plan trip cap surfaces the Pro paywall instead of a raw error.

### Trip detail — 5 tabs: Stats · Stops · Crew · Expenses · Pack

**Stats tab**
- 2×2 grid: Distance, Max speed, Avg speed, Duration (unit-aware).
- Conditional tiles: Avg fuel cost, Fuel cost/km or /mi, and (when a route is planned) an estimated fuel cost projected across the whole route polyline.
- Pull-to-refresh forces a stats recompute from raw location pings.

**Stops tab**
- **Next-stop banner**: shows the next un-arrived stop's live distance and an ETA derived from the trip's average speed.
- Drag-to-reorder (`ReorderableListView`), persisted atomically server-side.
- Swipe-to-delete with confirm dialog.
- Each stop shows a kind icon (food/scenery/fuel/rest/custom), name, optional planned-arrival time, and notes.

**Expenses tab**
- Running total + per-category breakdown chips (e.g. "fuel: $40.00").
- Swipe-to-delete with confirm dialog.

**Pack tab**
- A shared per-trip packing/prep checklist ("who's bringing what") — any participant can add, tick off, or remove an item.
- Header shows a "Packed N/M" pill and progress bar.

**Header actions**: photo-gallery icon, "Complete" button (active trips only), overflow menu — **Trip recap**, **Save route** (when the trip has a planned route), **Share live link** / **Stop live link** (creator only), and Delete (creator only) / Leave.

### Add stop
- Auto-resolves device GPS as the default pin location; "Pick on map" opens a drag-to-place picker.
- Kind selector: Food / Scenery / Fuel / Rest / Custom.
- Name required (≤60 chars), notes optional (≤500 chars).
- Optional planned-arrival date/time pickers.
- **Offline-aware**: on network failure, queues into the offline outbox instead of failing — toast "You're offline — this stop will sync when you reconnect."

### Add expense
- Categories: Fuel / Food / Toll / Lodging / Other.
- Amount required: rejects unparsable input ("Enter a valid amount"), ≤0 ("Amount must be greater than zero"), or over $1,000,000 ("Amount is too large").
- Fuel category unlocks optional Liters + Odometer fields.
- Same offline-outbox fallback as stops.

### Route planning
- Origin defaults to device GPS; both origin/destination are pickable on an embedded preview map.
- "Find routes" fetches multiple alternate routes via the Directions API, rendered as polylines — selected route highlighted, others dimmed.
- Each route tile shows "distance · duration" (e.g. "12.3 km · 18 min").
- "Use this route" saves the polyline onto the trip.

### Trip recap & saved routes
- **Trip recap** (trip menu → "Trip recap"): a shareable post-drive summary — the route (origin → destination), date, crew count, a 2×2 stat grid (distance, moving time, top speed, average), the speed profile sparkline, a per-category **spend** breakdown, and a link to the trip's photos. "Share recap" exports a one-line summary via the system share sheet.
- **Saved routes**: save a trip's planned route to a personal template library (trip menu → "Save route"), then reuse it when creating a trip (New trip → "Saved"). Templates are private to their owner.
- **Weather en route**: for each stop that has a planned arrival time, the Stops tab shows the forecast at that hour (icon, temperature, rain %) from Open-Meteo (no API key) via the server's `/weather` proxy. Best-effort — hidden when unavailable, never fabricated.

### Watch live link (share a trip with anyone)
- The trip's creator can mint a **public read-only link** (trip menu → "Share live link") that anyone can open with no account — e.g. family following the crew.
- The page is self-contained (server-rendered HTML at `/watch/<token>`): the route drawn as an SVG with each rider's latest position, refreshing every 15s. No map SDK, no token to leak.
- **Revocable**: "Stop live link" deletes the share (creator-only RLS on `trip_shares`); a revoked/unknown token is a plain 404.

---

## 8. Social — Friends & Groups

### Friends
- 3 tabs: **Friends**, **Requests** (Incoming/Outgoing), **Find people**.
- Find people: search requires ≥2 characters, "Add" sends a request and flips to "Requested" locally to block double-sends.
- Removing a friend requires confirmation ("Remove @username from your friends?").
- Declining a request deletes the row (not a soft "blocked" state), so a future re-request is possible.

### Groups
- Empty state: "No groups yet. Groups are shared crews you plan and take trips with. Create one, or join with an invite code." + "New group" and "Join with a code" actions.
- **Create** a group: name ≤60 chars; it gets its own generated identicon avatars and a revocable invite code.
- **Join** a group three ways: an admin adds you as a friend, you type an invite code, or you open a shared invite link (`https://<host>/join/<code>` / `com.ranmap.app://join/<code>`). A signed-out recipient's code survives the sign-up round trip and re-opens the join screen afterwards. Joining shows a preview of the group (name, description, member count) before you commit.
- **Roles**: owner / admin / member. The owner is unique; admins can add/remove members, approve join requests, edit the group, manage the invite link, and promote/demote members (never the owner).
- **Promote / demote**: tap a member (admins only) → "Make admin" / "Dismiss as admin".
- **Join approval**: an admin can require approval for the invite link; new arrivals land as *pending*, and admins approve/deny from a "Join requests" section.
- **Ownership transfer**: the owner can hand the group to another member ("Make owner"); the previous owner stays on as an admin.
- **Leaving**: members leave freely; an owner must transfer first (or, as the last member, leaving deletes the group). A separate "Delete group" (owner-only) deletes it for everyone.
- **Edit group**: name, description (≤200 chars) and a shuffleable group avatar.
- **Invite link**: every member can copy/share the link and code; admins can toggle approval and reset (rotate) the link.
- "Add member" hits the free-tier group-size cap → shows the Pro paywall instead of an error. Adding a friend directly still requires having friends first — otherwise toast "Add friends first, then invite them to a group."
- Trips can be planned *for* a group (New trip → Group), which links the trip to the crew; the trip's Crew tab shows and opens the group.

### Group live convoy (the core idea, at group scope)
- **Live convoy screen** (Group detail → "Live convoy"): the group as a persistent convoy, independent of any trip.
- **Share my location** toggle: turns on group presence (persisted, one active convoy at a time); your crew sees you live while it's on. Reuses the same server-attested broadcast as trips, on a group-scoped channel (`group-locations:<id>`).
- **Live crew roster**: each member's real avatar, live distance + bearing arrow, and a state pill — **Live**, **Stopped**, or **Behind** (client-computed from real positions/speed). Tap a member to hand off to turn-by-turn directions.
- **Convoy intelligence**: nearest-teammate safe-gap readout, a member flagged "Behind" past ~2 km, and "Stopped" when their speed drops to a standstill.
- **SOS**: one tap alerts the whole crew (with your live location) and pushes them a notification.
- **Regroup here**: shares a rendezvous point with your location; members who reach it (~150 m) are **auto-checked-in**, and the alert shows real "N/M arrived" progress. Admins can mark an alert resolved.
- **Quick statuses**: one-tap **Wait up**, **Stopping**, and **Need fuel** signals that surface to the whole crew as alerts.
- **SMS SOS fallback**: with an emergency contact set, a **Text emergency contact** action opens the device SMS composer pre-filled with "I need help" + your live map link — SMS works with no data, so it's the no-signal backup for the in-app SOS.
- **Crew photos**: a gallery of map photos members have shared with the group (Share to a group from any map photo).
- On the **main map**, when there's no active trip but a convoy is joined, the crew's live vehicles and roster appear exactly as they do on a trip.
- Presence is stored as a latest-known-position snapshot (coarse, self-pruning); live movement rides the ephemeral broadcast, so a stationary member ages out of presence after ~15 minutes.

---

## 9. Premium / Ranmap Pro & Paywall

- **Tiers**: `free` < `pro` < `extreme`. `is_pro` means *paid* (pro OR extreme),
  so **Extreme inherits every Pro gate**; `is_extreme` marks the top tier (a
  superset — same features, higher ceilings, no exclusive features).
- **Free-tier hard caps** (DB-trigger enforced, can't be bypassed by a patched client):
  - **3** max active/planned trips
  - **6** max group members (raising any one member to a paid tier lifts the cap for the whole group)
  - **25** max pinned photos
  - **1** max document and **1** max saved route
- **Paid fair-use ceilings** (`0033_pro_fair_use_limits.sql`, `0034_extreme_tier.sql`): paid tiers are **metered, not unlimited** — provider quota and storage cost real money. Pro raises the caps above to **100** trips, **100** members, **5,000** photos, **100** documents and **100** saved routes; **Extreme** raises them further to **250 / 250 / 20,000 / 500 / 500**. Hitting a paid ceiling raises a plain `Plan limit reached:` error (no paywall); a free account hitting a free cap raises `Ranmap Pro required:` (which opens the paywall).
- **Metered features**: AI assistant and route & place search. Free gets **500k AI tokens / 30 days** and **100 searches / day**; Pro **5M / 2,000**; Extreme **15M / 5,000**. Every paid tier is metered against its own ceiling too, so a single account can't run up an unbounded provider bill.
- **"Travel together" voice unlock**: voice channels unlock for an entire trip/group if *any* member is Pro — not per-seat.
- **Crew plan (already in place)**: because Pro is evaluated per trip/group (`trip_has_pro` / `group_has_pro`), one subscriber already covers their whole convoy — voice and the (much higher) trip/photo/member caps are lifted for everyone they travel with. This is the "one subscription, whole crew" model; no separate product is needed.
- **Full-screen paywall**: shown once after sign-in and weekly thereafter for non-Pro users (7-day cooldown, persisted across restarts). Shows annual vs. monthly plans (annual default, with a saving ribbon derived from the store's real prices — never a hard-coded number), a benefits list, "Restore Purchases", and a "Manage Subscription" deep link.
- **Contextual paywall sheet**: shown at the moment a specific limit is hit — "You reached a Pro limit for `<feature>`." with the same purchase/restore actions and a "Not now" dismiss.
- Billing runs through **RevenueCat**; `profiles.plan` is writable only by the server-side webhook, never the client. Purchase-cancel (dismissing the native store sheet) is swallowed silently, not shown as an error.

---

## 10. Live 3D Map

- **3D rendering** via Mapbox Standard: extruded buildings, trees, landmarks, terrain — this is a real 3D scene, not a flat map with icons.
- **Location permission gate**: full-screen prompt if denied ("Ranmap needs your location to show you on the map…") with "Allow location" and "Open settings" actions; auto-rechecks when the app resumes from background.
- **Short-lived Mapbox tokens**: fetched from the server, auto-refreshed 2 minutes before expiry, then the style silently reloads.
- **Camera**: default zoom 15.5, pitch 45° (tilted for the 3D effect); "Recenter on me" FAB flies back with a 900ms animation.
- **You are represented by your own 3D vehicle model**, not a flat dot, rotated to your heading.
- **Status card**: "No active trip" or "`<trip title>` · N teammates live" — tap to open the live-teammates list. When no trip is active but a group convoy is joined, the card and teammate layer show that crew instead (see §8).
- **Background tracking**: continues while backgrounded during an active trip or a joined group convoy (Android foreground service with a persistent notification "Ranmap is sharing your location"; iOS background location with `automotiveNavigation` activity type). 5-meter distance filter, high accuracy.
- **Live sync error chip**: shown if the realtime location/photo stream errors, with a retry button — "Live teammates aren't updating."

### Basemap & toggles
- **Basemap cycle** (single FAB): Standard → Satellite → Outdoors → back to Standard.
- **3D buildings toggle**: only works on Standard/Satellite (Outdoors has no 3D import — toggling there silently no-ops).
- **Terrain toggle**: works on all 3 basemaps, uses a dedicated DEM source with 1.35× exaggeration.
- **Automatic time-of-day lighting**: night/dawn/dusk/day preset chosen from the real clock (not user-selectable) — e.g. "night" before 6am or at/after 8pm.

### Offline maps
- A map control opens **Offline maps**: download a trip's route area as Mapbox tile packs (bounding box around the decoded route, padded), for the current basemap style.
- Saved regions are listed with their size and tile count, and can be deleted. Downloads show live progress. Once present, the SDK serves tiles from disk, so the route renders with no signal.
- Rendered by the Mapbox `TileStore`; no extra credential — it uses the same short-lived rendering token the map does.

### Vehicle models
- Bundled low-poly glTF models per vehicle type (car/bike/scooter/SUV), generated by a Python tool since no binary art ships in the repo.
- Each teammate gets their own model layer so headings can differ independently; only-moved vehicles get an in-place rotation/position update rather than a full re-add (efficient diffing).
- Switching vehicle type mid-trip removes and re-adds the correct model.

### Navigate to friend
- Tap a teammate in the live list → shows distance + 8-point compass direction (e.g. "1.2 mi away · NE").
- "Navigate to them" hands off to the native Google Maps app for turn-by-turn directions, using the correct travel mode (bicycling for bikes, driving otherwise — scooters map to driving since Google has no scooter mode).
- (Vehicles aren't directly tappable on the map itself — Mapbox Standard doesn't support querying 3D model layers — so the teammate list is the tap target.)

---

## 11. Photo Sharing

- Camera FAB (visible during an active trip) opens capture/pick flow: camera or gallery, compressed to 85% quality / max 1920px width.
- Optional caption, ≤200 characters.
- Photos upload to a **private** storage bucket and are pinned to your current GPS location — always current position, no manual placement for photos.
- Viewing a pin opens a sheet with a signed URL (1-hour expiry), poster's `@username`, and timestamp.
- **Delete own photo**: confirm dialog "This photo will be removed for everyone." — only the poster sees this option.
- Hitting the free photo cap (25) shows the Pro paywall instead of a raw error.
- **Trip photo gallery**: a 3-column grid of every photo pinned to a trip, as an alternative to hunting for pins on the map — accessible from the trip's app bar.
- Pins render as a custom teardrop marker with a camera icon.

---

## 12. Nearby Places & Route Search

- **Category filters**: Food, Fuel, Lodging, Sights (default: Food) — tapping a chip re-runs the search immediately.
- Default search radius: 5 km around the map's current center.
- **Search along the route**: toggle appears only when the active trip has a planned route — searches the *entire route* in one request instead of just your current position, so you can find fuel/food that's actually on the way.
- Tapping a result opens **place details**: star rating with review count (e.g. "★ 4.6 (3,812)"), price level ($–$$$$), "Open now"/"Closed" status, and weekday hours — fetched from Google's Places API only when you open a single place (not for every search result, to control cost).
- "Pin on map" drops a marker at the selected place and flies the camera there.
- **Pick-location screen**: fixed center-pin pattern — you drag the map, not the pin — used for manual stop placement, route origin/destination, etc.

---

## 13. Chat & Voice

### Hub
- Two tabs: **AI Assistant** and **Group Chat**, reached via the bottom-nav "Chat" tab.
- Each trip and each group gets its own channel automatically.

### Group text chat
- Message limit: **4,000 characters**, enforced both client-side (visual counter) and matched server-side.
- **Offline-safe sending**: messages queue into a persisted outbox if you're offline, with a client-generated UUID reused on replay so retries can never create duplicates.
- Realtime sync via Supabase Realtime — new messages from others appear automatically.
- Long-press your own message to delete it ("This message will be removed for everyone.").
- Empty state: "No messages yet — say hi!"

### Voice channels
- LiveKit-powered audio room per trip/group, joined explicitly (not auto-joined).
- Mute/unmute toggle, leave button, live participant list with **speaking indicators** (green highlight) and mute icons per participant.
- **Push-to-talk**: a mode switch turns the channel into a walkie-talkie — the mic stays muted until you hold **"Hold to talk"**, opening only while pressed (the convoy's native interaction).
- **Auto-reconnect** with exponential backoff (1s → 2s → 4s → 8s → 16s, capped at 30s, up to 5 attempts) if the connection drops, showing "Reconnecting…" without tearing down the UI.
- Unlocked for an entire trip/group if any member has Ranmap Pro — shown via a "Pro voice — unlocked for everyone here" banner.
- Server enforces trip/group membership before minting a voice token (403 if you're not a member), plus a rate limit of 30 joins per 10 minutes.

### AI Trip Assistant
- Chat-style interface; empty-state prompt suggests example requests: *"save Joshua Tree as a stop"*, *"create a trip called Road Trip"*, *"schedule Road Trip for next Friday at 8am"*.
- Conversation history browsable/resumable (`AiConversationsScreen`); swipe-to-delete a conversation.
- Message limit: 4,000 characters, same as group chat.
- Optimistic local echo while waiting for the server, reconciled once the real message streams back.

- Powered by **Gemini 3.1 Flash-Lite** (Interactions API) with **Google Search grounding** enabled, so it can answer current-information questions (opening hours, road/weather conditions, events) grounded in real web results, alongside its own tools.

**6 tools the assistant can call:**
1. **`save_place`** — saves a mentioned place to your saved-places list. *"remember Joshua Tree as a place I want to visit"* → saved with optional coordinates.
2. **`create_trip`** — creates a new trip and enrolls you as its first member, optionally scheduling it in the same step. *"create a trip called Road Trip"*.
3. **`schedule_trip`** — schedules one of your *existing* trips (found by exact title) to auto-start at a future time. *"schedule Road Trip for next Friday at 8am"*.
4. **`invite_friend_to_trip`** — looks up a friend by exact username and adds them to a trip you're on, sending a push notification. *"invite alice_j to Road Trip"*.
5. **`add_stop`** — geocodes and appends a located stop to one of your trips. *"add a stop at the Grand Canyon"*.
6. **`propose_stop`** — proposes a stop for the convoy to vote on instead of adding it directly. *"propose a stop at the Grand Canyon"*.

- All tool inputs are validated server-side (lat/lng ranges, future-only schedule times, allowlisted stop kinds) and every free-text field is clamped to prevent unbounded LLM-generated content from being written to the database.
- Free tier: **500k tokens per 30 days** (input + output, summed across every model call in a turn), then gated behind Pro with the message: "You've used your free AI assistant allowance. Upgrade to Ranmap Pro for a much larger allowance." Pro is metered against a **5M-token / 30-day** fair-use ceiling too (a Pro user past it gets a plain "limit reached", not a paywall). The Profile tab shows a live **Free plan usage** meter (from `GET /plan/usage`) so the allowance is visible before it runs out.
- A background scheduler (polling every 60s) auto-starts trips whose scheduled time has arrived.

---

## 14. Live Location Sync & Stats

- While a trip is active, live positions travel over a **private Supabase Realtime broadcast channel** per trip (`trip-locations:<trip_id>`, RLS on `realtime.messages` — accepted members only). A **group convoy** uses the same mechanism on a group-scoped channel (`group-locations:<group_id>`, active members only), plus a coarse latest-known-position snapshot (`group_locations`) that heals a cold start. Positions are ephemeral: no database write per fix, and none of the insert fan-out the old design had. A teammate's position appears on the map as it changes (broadcasts are throttled to ~1/s).
- Broadcasting goes through the **`broadcast_position` RPC**: it verifies the caller's trip membership via `auth.uid()` and emits the broadcast with the **sender id stamped by the database**, so a member cannot forge another member's position. Clients can't publish on the channel directly (the client INSERT policy is revoked).
- The `trip_member_locations` RPC is still fetched on every (re)subscribe as the **authoritative cold-start/reconcile path** — a broadcast is fire-and-forget, so a missed message (offline, reconnect) is healed by the next snapshot rather than showing a stale dot forever.
- The **persisted trail** (`location_pings`) is written only every ~45s per rider for statistics and history — roughly a 50–100× reduction in rows versus one write per 5 m of movement.
- **Stats dashboard** (distance, max/avg speed, duration) is recomputed automatically every 4 persisted pings during an active trip, from haversine distance between consecutive points — and once more, forced, when you complete the trip.
- **Fuel cost estimation**: derives a $/km rate from logged fuel expenses and applies it to the planned route's full distance for an estimated total fuel cost.

---

## 15. Offline Handling

- App-wide connectivity banner reflects online/offline/syncing state:
  - Offline with pending writes: "You're offline — N change(s) will sync when you reconnect."
  - Syncing: "Syncing N pending change(s)…"
  - Permanently failed writes (e.g. rejected by validation): "N change(s) couldn't be saved and were lost. Please try again." — dismissible.
- Writes made offline (chat messages, expenses, stops) queue in a **persisted outbox** and replay automatically on reconnect — plus a periodic 20-second sweep as a backup in case a connectivity event is missed.
- Replay is **idempotent**: each queued write carries a client-generated UUID reused on retry, so a crash-and-retry can never create a duplicate row.
- Failures are classified as retryable (network errors, transient DB errors) vs. permanent (validation/RLS rejections) — a permanent failure drops just that one entry instead of blocking the whole queue.
- Settings → Data → "Clear offline queue" permanently discards anything still waiting to sync (with a confirmation dialog).

---

## 16. Push Notifications (server-ready, partially wired)

- Server registers device tokens and delivers via FCM when configured; fires on trip invitations, group invites/join requests, and convoy alerts (SOS / regroup).
- Settings → Notifications lets you opt in/out per category (trip invites, chat, group invites, trip updates).
- **Not yet complete**: the Flutter client doesn't obtain an FCM token yet, so nothing is actually delivered to devices today — this is explicitly a "server-ready" feature.

---

## 17. Theming & Units

- Light/dark theme, following system setting or your explicit choice.
- Distance and speed formatting respects your km/mi preference everywhere — e.g. "80 km/h" vs "50 mph", "12.4 km" vs "7.7 mi", and short-distance readouts switch to meters/feet under 1km/0.1mi (e.g. "320 ft away").

---

## 18. Security & Architecture Notes (relevant to what "features" actually mean here)

- The client never holds an LLM, Twilio, Mapbox, or LiveKit secret key — all privileged operations go through `ranmap-server`, which verifies the forwarded Supabase session token first.
- Paid-plan flags are enforced **server-side and at the database level** (RLS + triggers), so a patched client can't unlock Pro features or bypass caps.
- Optional integrations (Maps, phone verification, voice, billing) degrade gracefully to a clear `503`/"not configured" response instead of crashing the server when their env vars are unset.
