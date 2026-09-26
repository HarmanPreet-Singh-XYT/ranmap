/// Client-side mirror of the server's free-tier limits, which live in
/// `public.plan_limit()` (supabase/migrations/0010_plan_limits.sql). Kept here
/// so marketing surfaces (the paywall comparison table) can't drift from what
/// the DB actually enforces. The server remains authoritative.
library;

/// Non-completed (`planned` / `active`) trips a free account may hold at once.
const int kFreeTripLimit = 3;

/// Members a non-Pro group may hold.
const int kFreeGroupMemberLimit = 6;

/// Photo map pins a free account may create.
const int kFreeMapPostLimit = 25;
