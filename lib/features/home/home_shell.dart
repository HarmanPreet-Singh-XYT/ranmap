import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/router/auth_state_provider.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/models/trip.dart';
import '../chat/chat_hub_screen.dart';
import '../premium/paywall_gate.dart';
import '../social/invite_landing_screen.dart';
import '../social/invite_providers.dart';
import '../social/social_providers.dart';
import '../trip/trip_list_screen.dart';
import '../trip/trip_providers.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';

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
  }

  /// Offers a deep-link invite once the user is signed in with a profile. A
  /// signed-in recipient already handled it on the invite screen (which clears
  /// the pending value), so this fires mainly for someone who signed up from an
  /// invite link and has now landed home.
  Future<void> _maybeShowPendingInvite() async {
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

    // Don't stack the sheet on top of another route (e.g. the paywall).
    if (ModalRoute.of(context)?.isCurrent != true) return;

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
    // A pending invite can arrive (or the profile resolve) after the first
    // frame; offer it once both are ready.
    ref.listen(myProfileProvider, (_, next) {
      if (next.valueOrNull != null) _maybeShowPendingInvite();
    });
    ref.listen(pendingInviteProvider, (_, next) {
      if (next != null) _maybeShowPendingInvite();
    });

    // Inbound signals had no home: a trip invite or friend request sat unseen
    // behind Profile → Friends. Badge the tabs that surface them instead.
    final inviteCount = ref.watch(tripInvitesProvider).valueOrNull?.length ?? 0;
    final requestCount =
        ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;

    return FScaffold(
      // Screens own their own padding/background (the map especially).
      childPad: false,
      footer: FBottomNavigationBar(
        index: _index,
        onChange: (i) => setState(() {
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
            icon: _NavBadge(count: inviteCount, icon: Icons.route_rounded),
            label: const Text('Trips'),
          ),
          const FBottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: Text('Chat'),
          ),
          FBottomNavigationBarItem(
            icon: _NavBadge(count: requestCount, icon: Icons.person_rounded),
            label: const Text('Profile'),
          ),
        ],
      ),
      // Surfaces the non-Pro paywall once after onboarding and weekly after.
      child: PaywallGate(
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
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
