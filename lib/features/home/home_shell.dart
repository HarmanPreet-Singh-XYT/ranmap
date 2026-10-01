import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/feedback/app_feedback.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/trip.dart';
import '../../core/providers/settings_provider.dart';
import '../chat/chat_hub_screen.dart';
import '../chat/chat_providers.dart';
import '../chat/voice_mini_bar.dart';
import '../map/map_navigation.dart';
import 'realtime_sync.dart';
import '../chat/voice_session.dart';
import '../premium/paywall_gate.dart';
import '../social/invite_landing_screen.dart';
import '../social/invite_providers.dart';
import '../social/social_providers.dart';
import '../trip/trip_list_screen.dart';
import '../trip/trip_providers.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';

/// True while the screen should be held awake: a trip is active and the user
/// hasn't turned "Keep screen on during trips" off.
final _keepScreenAwakeProvider = Provider.autoDispose<bool>((ref) {
  final enabled = ref.watch(appSettingsProvider.select((s) => s.keepScreenOn));
  final hasActiveTrip = ref.watch(activeTripProvider).valueOrNull != null;
  return enabled && hasActiveTrip;
});

/// Bottom-nav shell hosting the four primary destinations.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// The shell opens on Trips (see [_decideLandingTab]) so the Map — and its
  /// location prompt — isn't the first thing a brand-new user meets.
  int _index = _tripsTab;

  /// Tabs are built lazily on first visit, so the map's GPS/permission work and
  /// the profile's provider fan-out don't all fire at launch. Once visited a tab
  /// stays mounted (IndexedStack preserves state).
  final Set<int> _visited = {_tripsTab};

  /// Set once the user taps a tab, so the landing decision never switches the
  /// tab out from under them.
  bool _userNavigated = false;

  /// Whether the opening tab has been decided. The shell renders immediately on
  /// Trips and only moves to the Map once a non-empty trips lookup resolves, so
  /// a brand-new user never meets the Map's location prompt — without blocking
  /// the UI behind a spinner.
  bool _landingDecided = false;

  /// Session latch for the pending-invite prompt, so it's presented once.
  bool _invitePromptActive = false;

  /// Whether the launch-time active trip has been offered auto-join.
  bool _voiceChecked = false;

  /// Joins voice for a trip that just became active and leaves when it ends.
  /// Deferred a frame: it changes another provider, which isn't allowed while
  /// this widget is building.
  void _syncVoiceToActiveTrip(Trip? previous, Trip? next) {
    Future.microtask(() {
      if (!mounted) return;
      final voice = ref.read(voiceSessionProvider.notifier);
      if (next != null && next.id != previous?.id) {
        final channel = ChatChannel.trip(next.id);
        if (!ref.read(appSettingsProvider).voiceAutoJoin) {
          _offerVoice(channel, next.title);
          return;
        }
        if (voice.wasLeftByUser(channel)) return;
        // Don't yank someone out of a call they started elsewhere.
        final current = ref.read(voiceSessionProvider);
        if (current.inCall && current.channel != channel) return;
        unawaited(voice.join(channel, title: next.title, auto: true));
      } else if (next == null && previous != null) {
        final current = ref.read(voiceSessionProvider);
        if (current.channel == ChatChannel.trip(previous.id)) {
          unawaited(voice.leave(byUser: false));
        }
      }
    });
  }

  /// Voice is opt-in: when a trip starts without auto-join, offer a one-tap join
  /// instead of connecting everyone's mic and speaker unasked.
  void _offerVoice(ChatChannel channel, String title) {
    final voice = ref.read(voiceSessionProvider.notifier);
    if (voice.wasLeftByUser(channel)) return;
    if (ref.read(voiceSessionProvider).inCall) return;
    showFToast(
      context: context,
      title: const Text('Trip started'),
      description: const Text('Join the convoy voice channel?'),
      icon: const Icon(Icons.headset_mic_rounded),
      alignment: FToastAlignment.bottomCenter,
      duration: const Duration(seconds: 8),
      suffixBuilder: (context, entry) => FButton(
        variant: FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        onPress: () {
          entry.dismiss();
          unawaited(voice.join(channel, title: title));
        },
        child: const Text('Join'),
      ),
    );
  }

  /// The last wake-lock state pushed to the platform.
  bool _wakeApplied = false;

  @override
  void dispose() {
    // Never leave the screen locked awake once the shell is gone (sign-out).
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  static const int _mapTab = 0;
  static const int _tripsTab = 1;

  static const _screens = [
    MapScreen(),
    TripListScreen(),
    ChatHubScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decideLandingTab());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowPendingInvite(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeResumeGroupJoin(),
    );
  }

  /// Re-attempts [action] shortly after [attempt] while another route is on
  /// top, so a pending invite isn't silently dropped when the shell wasn't
  /// current (e.g. the post-sign-in paywall was showing). Bounded so it can't
  /// loop forever.
  void _retryWhenCurrent(int attempt, Future<void> Function() action) {
    if (attempt >= 10) return;
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) action();
    });
  }

  /// Re-opens a group join link the user tapped before signing up. The code is
  /// persisted across the auth round trip, so once they're home with a profile
  /// we push the join screen; it clears the pending code on entry.
  Future<void> _maybeResumeGroupJoin({int attempt = 0}) async {
    if (!mounted) return;
    final code = ref.read(pendingGroupJoinProvider);
    if (code == null) return;
    if (ref.read(authStateProvider).valueOrNull?.session == null) return;
    if (ref.read(myProfileProvider).valueOrNull == null) return;
    // Don't stack it on top of another route (e.g. the paywall) — retry once
    // that route is gone, rather than dropping the pending code.
    if (ModalRoute.of(context)?.isCurrent != true) {
      _retryWhenCurrent(
        attempt,
        () => _maybeResumeGroupJoin(attempt: attempt + 1),
      );
      return;
    }
    await context.push('/join/$code');
  }

  /// Offers a deep-link invite once the user is signed in with a profile. A
  /// signed-in recipient already handled it on the invite screen (which clears
  /// the pending value), so this fires mainly for someone who signed up from an
  /// invite link and has now landed home.
  Future<void> _maybeShowPendingInvite({int attempt = 0}) async {
    if (!mounted || _invitePromptActive) return;
    final username = ref.read(pendingInviteProvider);
    if (username == null) return;
    if (ref.read(authStateProvider).valueOrNull?.session == null) return;

    final me = ref.read(myProfileProvider).valueOrNull;
    if (me == null) return;
    if (me.username == username) {
      await ref.read(pendingInviteProvider.notifier).clear();
      return;
    }

    // Don't stack the sheet on top of another route (e.g. the paywall) — retry
    // once that route is gone, rather than dropping the pending invite.
    if (ModalRoute.of(context)?.isCurrent != true) {
      _retryWhenCurrent(
        attempt,
        () => _maybeShowPendingInvite(attempt: attempt + 1),
      );
      return;
    }

    _invitePromptActive = true;
    try {
      final add = await showPendingInvitePrompt(context, username: username);
      if (add == true) {
        try {
          final sent = await ref
              .read(friendRepositoryProvider)
              .sendRequestByUsername(username);
          if (mounted) {
            showAppToast(
              context,
              sent
                  ? 'Friend request sent to @$username.'
                  : 'No user found with username "$username".',
              error: !sent,
            );
          }
        } catch (e) {
          if (mounted) showAppToast(context, friendlyError(e), error: true);
        }
      }
    } finally {
      if (mounted) _invitePromptActive = false;
      await ref.read(pendingInviteProvider.notifier).clear();
    }
  }

  /// Moves a user who already has a trip onto the Map (the shell's real home
  /// for them). The shell renders on Trips from the first frame, so this never
  /// blocks — a slow or failed lookup just leaves them on Trips, one tap from
  /// the Map.
  Future<void> _decideLandingTab() async {
    if (_landingDecided) return;

    List<Trip>? trips;
    try {
      trips = await ref
          .read(myTripsProvider.future)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      trips = null;
    }
    if (!mounted || _landingDecided) return;

    setState(() {
      _landingDecided = true;
      if (!_userNavigated && trips != null && trips.isNotEmpty) {
        _index = _mapTab;
        _visited.add(_mapTab);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep the trips lookup alive across the landing decision (it's read as a
    // future in [_decideLandingTab], which doesn't hold a subscription of its
    // own).
    ref.watch(myTripsProvider);
    // Live updates: friend requests, trips, groups and notifications refresh as
    // they change, not on the next app launch.
    ref.watch(realtimeSyncProvider);
    // "Navigate here" raised anywhere (chat location, saved place) lands on the
    // map, which draws the route in-app.
    ref.listen(mapNavRequestProvider, (_, next) {
      if (next == null) return;
      setState(() {
        _index = _mapTab;
        _visited.add(_mapTab);
        _userNavigated = true;
      });
    });
    // A pending invite can arrive (or the profile resolve) after the first
    // frame; offer it once both are ready.
    ref.listen(myProfileProvider, (_, next) {
      if (next.valueOrNull != null) {
        _maybeShowPendingInvite();
        _maybeResumeGroupJoin();
      }
    });
    ref.listen(pendingInviteProvider, (_, next) {
      if (next != null) _maybeShowPendingInvite();
    });
    ref.listen(pendingGroupJoinProvider, (_, next) {
      if (next != null) _maybeResumeGroupJoin();
    });
    // Keep the screen awake while driving a trip so the map doesn't go dark.
    // Applied only when the value changes (the platform call is idempotent and
    // touches no provider state, so it's safe to trigger from build).
    final keepAwake = ref.watch(_keepScreenAwakeProvider);
    if (_wakeApplied != keepAwake) {
      _wakeApplied = keepAwake;
      unawaited(keepAwake ? WakelockPlus.enable() : WakelockPlus.disable());
    }
    // Always-on voice: join the trip's channel when it goes active, and drop
    // out when it ends.
    ref.listen(activeTripProvider, (previous, next) {
      // Sharing is on by default for every new trip: a pause from an earlier
      // trip must not leave this crew invisible until someone digs into Settings.
      final started = next.valueOrNull;
      final before = previous?.valueOrNull;
      // Trip lifecycle fanfares: only on a real transition, not first load.
      if (previous != null && previous.hasValue) {
        if (before == null && started != null) {
          AppFeedback.success();
          AppFeedback.play(Sfx.tripStart);
        } else if (before != null && started == null) {
          AppFeedback.medium();
          AppFeedback.play(Sfx.tripEnd);
        }
      }
      if (started != null && started.id != previous?.valueOrNull?.id) {
        final settings = ref.read(appSettingsProvider);
        if (!settings.shareLocation) {
          Future.microtask(
            () => ref.read(appSettingsProvider.notifier).setShareLocation(true),
          );
        }
      }
      _syncVoiceToActiveTrip(previous?.valueOrNull, next.valueOrNull);
    });
    // The provider may already hold an active trip when the shell mounts (a
    // trip started earlier); ref.listen only fires on change.
    if (!_voiceChecked) {
      final active = ref.watch(activeTripProvider).valueOrNull;
      if (active != null) {
        _voiceChecked = true;
        _syncVoiceToActiveTrip(null, active);
      }
    }

    // Inbound signals had no home: a trip invite or friend request sat unseen
    // behind Profile → Friends. Badge the tabs that surface them instead.
    final inviteCount = ref.watch(tripInvitesProvider).valueOrNull?.length ?? 0;
    final requestCount =
        ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;

    // Minimal map: the tab bar steps out of the way on the map tab (tapping the
    // eye button there brings everything back).
    final hideNav =
        _index == _mapTab &&
        ref.watch(appSettingsProvider.select((s) => s.mapMinimal));

    return FScaffold(
      // Screens own their own padding/background (the map especially).
      childPad: false,
      footer: hideNav
          ? null
          : FBottomNavigationBar(
              index: _index,
              onChange: (i) => setState(() {
                if (i != _index) AppFeedback.selection();
                _index = i;
                _visited.add(i);
                _userNavigated = true;
              }),
              children: [
                const FBottomNavigationBarItem(
                  icon: Icon(Icons.map_rounded),
                  label: Text('Map'),
                ),
                FBottomNavigationBarItem(
                  icon: _NavBadge(
                    count: inviteCount,
                    icon: Icons.route_rounded,
                  ),
                  label: const Text('Trips'),
                ),
                const FBottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_rounded),
                  label: Text('Chat'),
                ),
                FBottomNavigationBarItem(
                  icon: _NavBadge(
                    count: requestCount,
                    icon: Icons.person_rounded,
                  ),
                  label: const Text('Profile'),
                ),
              ],
            ),
      // Surfaces the non-Pro paywall once after onboarding and weekly after.
      child: Column(
        children: [
          Expanded(
            child: PaywallGate(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < _screens.length; i++)
                    _visited.contains(i)
                        ? _screens[i]
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
          // Above the bottom nav, clear of the status bar / notch.
          const VoiceMiniBar(),
        ],
      ),
    );
  }
}

/// A bottom-nav icon carrying a small count badge (hidden when [count] is 0).
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.icon});

  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Icon(icon),
    );
  }
}
