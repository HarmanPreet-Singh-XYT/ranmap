// Shared defaults and tunables that were previously repeated as inline magic
// values. Domain defaults mirror the Postgres column defaults so a row built
// client-side matches one the database would build.

/// Visibility a new map post is created with. Mirrors `map_posts.visibility`.
const String kDefaultMapPostVisibility = 'group';

/// Conversation id the AI backend reads as "start a new conversation" rather
/// than continuing an existing one.
const String kNewConversationId = 'new';

/// How long a one-shot GPS fix may take before the UI gives up and surfaces an
/// error, so a hung location provider can't strand the user on a spinner.
const Duration kLocationFixTimeout = Duration(seconds: 15);

/// Camera zoom while following the user or framing a single known point.
const double kFollowZoom = 15.5;

/// Camera zoom when focusing a searched or selected place.
const double kPlaceZoom = 16;

/// Zoom used when no center is known yet — a wide view the user can pan, rather
/// than an arbitrary point rendered at close range.
const double kFallbackMapZoom = 2;
