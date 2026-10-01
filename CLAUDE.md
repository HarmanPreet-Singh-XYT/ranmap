# Ranmap

Product promise: **ride together, stay in sync.** Ranmap is a group-travel
app (live map, voice, shared stops). Solo features (search, navigation, ride
recording, saved places) are an on-ramp, never the headline. Before changing
copy, the home screens or adding a feature, read "Product focus" in
`README.md` and keep the crew first.

- Flutter app in `lib/`, Next.js site in `web-app/`, backend in `server/`,
  database migrations in `supabase/migrations/`.
- Checks: `flutter analyze` and `flutter test` for the app; `npm test`,
  `npm run lint` and `npx tsc --noEmit` in `web-app/`; `npm test` in `server/`.
