import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/feedback/app_feedback.dart';
import '../../data/services/supabase_service.dart';
import '../map/map_post_providers.dart';
import '../notifications/notifications_providers.dart';
import '../premium/premium_providers.dart';
import '../settings/settings_providers.dart';
import '../social/social_providers.dart';
import '../trip/trip_providers.dart';

/// Keeps the app's cached server state in step with the database.
///
/// Most providers are one-shot fetches; without this a change made elsewhere (a
/// friend request from another account, a trip started by the host) stayed
/// invisible until the app restarted. One Realtime channel listens for
/// Postgres changes on the tables behind those providers (RLS limits events to
/// rows this user can read) and invalidates what depends on them. Events are
/// only "something changed" signals — the provider refetches the authoritative
/// rows — and bursts are coalesced per group.
///
/// Everything is also refreshed when the app returns to the foreground and
/// whenever the socket (re)connects, which heals events missed while
/// backgrounded or offline.
final realtimeSyncProvider = Provider.autoDispose<void>((ref) {
  if (SupabaseService.currentUser == null) return;

  final client = SupabaseService.client;
  final timers = <String, Timer>{};
  var disposed = false;
  var hasConnected = false;

  void friends() {
    ref.invalidate(friendsProvider);
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(outgoingRequestsProvider);
    ref.invalidate(blockedUsersProvider);
    ref.invalidate(friendshipWithProvider);
  }

  void groups() {
    ref.invalidate(myGroupsProvider);
    ref.invalidate(groupProvider);
    ref.invalidate(groupMembersProvider);
    ref.invalidate(commonGroupsProvider);
  }

  void trips() {
    ref.invalidate(myTripsProvider);
    ref.invalidate(activeTripsProvider);
    ref.invalidate(activeTripProvider);
    ref.invalidate(tripInvitesProvider);
    ref.invalidate(tripMembersProvider);
    ref.invalidate(myTripStatsProvider);
    ref.invalidate(commonTripsProvider);
  }

  void tripDetails() {
    ref.invalidate(tripStopsProvider);
    ref.invalidate(tripLegsProvider);
    ref.invalidate(tripExpensesProvider);
    ref.invalidate(tripChecklistProvider);
    ref.invalidate(tripProposalsProvider);
  }

  void notifications() {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  void photos() {
    ref.invalidate(tripMapPostsProvider);
    ref.invalidate(myMapPostsProvider);
    ref.invalidate(groupSharedPostsProvider);
    ref.invalidate(sharedWithMePostsProvider);
    ref.invalidate(allPhotosProvider);
  }

  final groupsByTable = <String, List<void Function()>>{
    'friendships': [friends, notifications],
    'user_blocks': [friends],
    'groups': [groups],
    'group_members': [groups],
    'trips': [trips, tripDetails],
    'trip_members': [trips, notifications],
    'trip_stops': [tripDetails],
    'trip_legs': [tripDetails],
    'trip_expenses': [tripDetails],
    'trip_checklist_items': [tripDetails],
    'stop_proposals': [tripDetails],
    'stop_votes': [tripDetails],
    'notifications': [notifications],
    'map_posts': [photos],
    'map_post_shares': [photos],
  };

  void schedule(String key, List<void Function()> actions) {
    if (disposed) return;
    timers[key]?.cancel();
    timers[key] = Timer(const Duration(milliseconds: 350), () {
      timers.remove(key);
      if (disposed) return;
      for (final action in actions) {
        action();
      }
    });
  }

  void refreshAll() {
    ref.invalidate(entitlementsProvider);
    ref.invalidate(notificationPreferencesProvider);
    friends();
    groups();
    trips();
    tripDetails();
    notifications();
    photos();
  }

  var channel = client.channel('app-sync-${SupabaseService.currentUser!.id}');
  for (final entry in groupsByTable.entries) {
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: entry.key,
      callback: (_) => schedule(entry.key, entry.value),
    );
  }
  // A brand-new notification (friend request, trip invite, convoy alert…)
  // addressed to this user: ping, even though the screens refresh via the
  // generic handler above. Realtime only delivers rows RLS lets us read.
  channel = channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'notifications',
    callback: (_) => AppFeedback.notify(),
  );
  channel.subscribe((status, error) {
    if (status != RealtimeSubscribeStatus.subscribed) return;
    // The first subscribe is the app's own cold start; every later one is a
    // reconnect, after which anything that changed meanwhile is stale.
    if (hasConnected) schedule('reconnect', [refreshAll]);
    hasConnected = true;
  });

  final observer = _ResumeObserver(() => schedule('resume', [refreshAll]));
  WidgetsBinding.instance.addObserver(observer);

  ref.onDispose(() {
    disposed = true;
    WidgetsBinding.instance.removeObserver(observer);
    for (final timer in timers.values) {
      timer.cancel();
    }
    unawaited(client.removeChannel(channel));
  });
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
