import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app-wide [SharedPreferences] instance. Overridden in `main()` with the
/// loaded instance so reads are synchronous everywhere else.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

// The intro is a two-step sequence: the v1 landing is the five-page feature
// tour, and the v2 screen is the welcome (email / Google / Apple) it hands off
// to. Kept as two flags so each step is walked exactly once.
const _kIntroV1SeenKey = 'intro_seen_v1';
const _kIntroV2SeenKey = 'intro_seen_v2';
const _kPaywallLastShownKey = 'paywall_last_shown_v1';
const _kPendingInviteKey = 'pending_invite_v1';
const _kPendingGroupCodeKey = 'pending_group_code_v1';
const _kConvoyGroupKey = 'convoy_group_v1';
const _kIntroFlagsVersionKey = 'intro_flags_version';

/// Bump when the *meaning* of the intro flags changes, so existing installs
/// re-walk the intro instead of skipping a step. v2: the five-page feature tour
/// became v1 and the welcome became v2 (previously both keys meant the welcome).
const int kIntroFlagsVersion = 2;

/// The intro flags whose meaning changed. Cleared once by [migrateIntroFlags].
const List<String> _introKeysToReset = [
  'intro_seen_v1',
  'intro_seen_v2',
  'feature_tour_seen_v1',
];

/// One-time reset of stale intro flags. Earlier builds stored these keys for
/// different screens, so a device that ran one would skip the current
/// `intro_seen_v1 → intro_seen_v2` sequence. Called once from `main()`.
Future<void> migrateIntroFlags(SharedPreferences prefs) async {
  if ((prefs.getInt(_kIntroFlagsVersionKey) ?? 0) >= kIntroFlagsVersion) return;
  for (final key in _introKeysToReset) {
    await prefs.remove(key);
  }
  await prefs.setInt(_kIntroFlagsVersionKey, kIntroFlagsVersion);
}

/// Small, typed facade over [SharedPreferences] for app-level flags.
class AppPrefs {
  const AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  /// Whether the v1 landing — the five-page feature tour — has been seen.
  bool get introV1Seen => _prefs.getBool(_kIntroV1SeenKey) ?? false;

  /// Records that the v1 landing (feature tour) has been seen.
  Future<void> markIntroV1Seen() => _prefs.setBool(_kIntroV1SeenKey, true);

  /// Whether the user has moved from the v2 welcome into an auth screen.
  ///
  /// Recorded so the two-step v1 → v2 intro is tracked, but it does *not* gate
  /// the signed-out landing: that stays the welcome once the v1 tour is done,
  /// so relaunching resumes on the welcome rather than jumping to sign-in.
  bool get introV2Seen => _prefs.getBool(_kIntroV2SeenKey) ?? false;

  /// Records that the welcome (v2) handed off into an auth screen.
  Future<void> markIntroV2Seen() => _prefs.setBool(_kIntroV2SeenKey, true);

  /// When the non-Pro paywall interstitial was last shown, or null if never.
  DateTime? get paywallLastShownAt {
    final millis = _prefs.getInt(_kPaywallLastShownKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Records that the paywall interstitial was shown, starting the weekly
  /// cooldown.
  Future<void> markPaywallShown(DateTime at) =>
      _prefs.setInt(_kPaywallLastShownKey, at.millisecondsSinceEpoch);

  /// The handle from an invite link that hasn't been accepted or declined yet,
  /// or null. Persisted so it survives the sign-up round trip — OAuth and email
  /// confirmation can both restart the process.
  String? get pendingInvite => _prefs.getString(_kPendingInviteKey);

  /// Records (or clears, when [username] is null) the pending invite handle.
  Future<void> setPendingInvite(String? username) {
    if (username == null) return _prefs.remove(_kPendingInviteKey);
    return _prefs.setString(_kPendingInviteKey, username);
  }

  /// The invite code from a group join link that hasn't been redeemed yet, or
  /// null. Persisted for the same reason as [pendingInvite]: a signed-out
  /// recipient must land back on the join screen after signing up.
  String? get pendingGroupCode => _prefs.getString(_kPendingGroupCodeKey);

  /// Records (or clears, when [code] is null) the pending group invite code.
  Future<void> setPendingGroupCode(String? code) {
    if (code == null) return _prefs.remove(_kPendingGroupCodeKey);
    return _prefs.setString(_kPendingGroupCodeKey, code);
  }

  /// The group whose live convoy the user is currently in, or null. At most
  /// one convoy at a time — it's the crew you're riding with right now — so a
  /// single id is enough, and it survives a restart so presence resumes.
  String? get convoyGroupId => _prefs.getString(_kConvoyGroupKey);

  /// Records (or clears, when [groupId] is null) the active convoy group.
  Future<void> setConvoyGroupId(String? groupId) {
    if (groupId == null) return _prefs.remove(_kConvoyGroupKey);
    return _prefs.setString(_kConvoyGroupKey, groupId);
  }
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
);
