import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_prefs_provider.dart';

/// The inviter's handle from a deep-link invite awaiting acceptance, if any.
///
/// Set when an invite link opens the app. A signed-in user accepts it from the
/// invite screen; a signed-out one keeps it across sign-up / onboarding, and
/// [HomeShell] offers it once they're back home.
///
/// Backed by [AppPrefs] rather than in-memory: the sign-up round trip (OAuth
/// bouncing through a browser, or an email confirmation) routinely restarts the
/// process, and an in-memory value would be lost exactly when it's needed.
class PendingInviteNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(appPrefsProvider).pendingInvite;

  Future<void> set(String username) async {
    state = username;
    await ref.read(appPrefsProvider).setPendingInvite(username);
  }

  Future<void> clear() async {
    state = null;
    await ref.read(appPrefsProvider).setPendingInvite(null);
  }
}

final pendingInviteProvider = NotifierProvider<PendingInviteNotifier, String?>(
  PendingInviteNotifier.new,
);

/// The group invite code from a deep-link awaiting redemption, if any.
///
/// Mirror of [PendingInviteNotifier] for group links: a signed-out recipient
/// who signs up from `/join/<code>` is returned to the join screen once home,
/// rather than losing the group.
class PendingGroupJoinNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(appPrefsProvider).pendingGroupCode;

  Future<void> set(String code) async {
    state = code;
    await ref.read(appPrefsProvider).setPendingGroupCode(code);
  }

  Future<void> clear() async {
    state = null;
    await ref.read(appPrefsProvider).setPendingGroupCode(null);
  }
}

final pendingGroupJoinProvider =
    NotifierProvider<PendingGroupJoinNotifier, String?>(
      PendingGroupJoinNotifier.new,
    );
