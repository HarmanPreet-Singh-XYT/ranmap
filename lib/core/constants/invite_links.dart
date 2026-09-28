/// Shareable invite links.
///
/// An invite points at the inviter's handle: opening it lets the recipient add
/// them as a friend (and, once signed in, sends the request). Two link forms
/// are recognised:
///
///  * The production web link — `https://<host>/invite/<username>`. Change
///    [kInviteHost] to the real domain when it exists. For the app to receive
///    it, the domain must serve `/.well-known/assetlinks.json` (Android App
///    Links) and `/.well-known/apple-app-site-association` (iOS Universal
///    Links), and the host must be listed in the Android intent-filter and the
///    iOS Associated Domains entitlement.
///  * The app's own scheme — `com.ranmap.app://invite/<username>` — which works
///    today on both platforms (the scheme is already registered for the OAuth
///    callback), so the flow is testable before a domain is chosen.
library;

/// The production invite host. Placeholder until the real domain is chosen —
/// update this *and* the Android intent-filter host and iOS associated domain
/// together.
const String kInviteHost = 'ranmap.app';

/// Whether [kInviteHost] points at a live domain that serves
/// `assetlinks.json` / `apple-app-site-association`.
///
/// While false, [inviteLinkFor] returns the custom-scheme link instead of the
/// dead `https://<placeholder>` URL, so a shared invite actually opens the app.
/// Flip this to true once the domain is live.
const bool kInviteHostConfigured = false;

/// The app's registered custom scheme (shared with the OAuth callback).
const String kInviteScheme = 'com.ranmap.app';

/// The invite link to share for [username]. Prefers the production web link
/// once the domain is live, and otherwise falls back to the custom-scheme link
/// (which works today, but only opens for people who already have the app).
String inviteLinkFor(String username) => kInviteHostConfigured
    ? 'https://$kInviteHost/invite/$username'
    : inviteSchemeLinkFor(username);

/// The custom-scheme invite link for [username]. Works on both platforms
/// without a domain (the scheme is already registered for the OAuth callback).
String inviteSchemeLinkFor(String username) =>
    '$kInviteScheme://invite/$username';

/// The inviter's handle carried by an incoming invite [uri], or null when the
/// URI isn't a Ranmap invite. Accepts both the web and custom-scheme forms.
String? inviteUsernameFromUri(Uri uri) {
  final isWebInvite = uri.scheme == 'https' && uri.host == kInviteHost;
  final isSchemeInvite = uri.scheme == kInviteScheme && uri.host == 'invite';
  if (!isWebInvite && !isSchemeInvite) return null;

  // Web form: the path is /invite/<username>.
  if (isWebInvite) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'invite') return segments[1];
    return null;
  }

  // Custom-scheme form: the host is 'invite' and the username is the first
  // path segment (com.ranmap.app://invite/<username>).
  final segments = uri.pathSegments;
  if (segments.isNotEmpty) return segments.first;
  return null;
}

/// The link to share for a group's invite [code]. Prefers the production web
/// link once the domain is live, and otherwise falls back to the custom-scheme
/// link (which opens the app directly).
String groupJoinLinkFor(String code) => kInviteHostConfigured
    ? 'https://$kInviteHost/join/$code'
    : groupJoinSchemeLinkFor(code);

/// The custom-scheme group link for [code].
String groupJoinSchemeLinkFor(String code) => '$kInviteScheme://join/$code';

/// The group invite code carried by an incoming link [uri], or null when the
/// URI isn't a Ranmap group invite. Accepts both the web
/// (`https://<host>/join/<code>`) and custom-scheme
/// (`com.ranmap.app://join/<code>`) forms.
String? groupJoinCodeFromUri(Uri uri) {
  final isWebJoin = uri.scheme == 'https' && uri.host == kInviteHost;
  final isSchemeJoin = uri.scheme == kInviteScheme && uri.host == 'join';
  if (!isWebJoin && !isSchemeJoin) return null;

  if (isWebJoin) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'join') return segments[1];
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.isNotEmpty) return segments.first;
  return null;
}
