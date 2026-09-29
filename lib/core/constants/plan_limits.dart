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

/// Documents a free account may keep in the private vault.
const int kFreeDocumentLimit = 1;

/// Saved route templates a free account may keep.
const int kFreeRouteTemplateLimit = 1;

// ---------------------------------------------------------------------------
// Pro fair-use ceilings. Pro is metered, not "unlimited": provider quota and
// storage cost real money, so each resource has a generous but finite ceiling.
// Mirrors `plan_limit()`'s *_pro keys in supabase/migrations/0033.
// ---------------------------------------------------------------------------

/// Non-completed trips a Pro account may hold at once.
const int kProTripLimit = 100;

/// Members a Pro convoy may hold.
const int kProGroupMemberLimit = 100;

/// Photo map pins a Pro account may create.
const int kProMapPostLimit = 5000;

/// Documents a Pro account may keep.
const int kProDocumentLimit = 100;

/// Saved route templates a Pro account may keep.
const int kProRouteTemplateLimit = 100;

// Extreme tier: the top plan, a strict superset of Pro with higher ceilings.
// Mirrors `plan_limit()`'s *_extreme keys in supabase/migrations/0034.
const int kExtremeTripLimit = 250;
const int kExtremeGroupMemberLimit = 250;
const int kExtremeMapPostLimit = 20000;
const int kExtremeDocumentLimit = 500;
const int kExtremeRouteTemplateLimit = 500;

// Metered allowances, mirroring server/src/lib/allowances.ts (free first, then
// the Pro and Extreme ceilings). Kept here so the paywall comparison can't drift
// from what the server actually enforces.
const int kFreeAiTokens = 500000;
const int kProAiTokens = 5000000;
const int kExtremeAiTokens = 15000000;
const int kFreeSearchPerDay = 100;
const int kProSearchPerDay = 2000;
const int kExtremeSearchPerDay = 5000;
