import 'dart:async';

import '../../core/widgets/pull_to_refresh.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:share_plus/share_plus.dart';

import 'package:intl/intl.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/env.dart';
import '../../core/constants/plan_limits.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/util/units.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/brand/brand_timeline.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/stop_proposal.dart';
import '../../data/models/trip.dart';
import '../../data/models/trip_expense.dart';
import '../../data/models/trip_leg.dart';
import '../../data/models/trip_stats.dart';
import '../../data/models/trip_stop.dart';
import '../../data/services/google_maps_api_service.dart';
import '../../data/services/supabase_service.dart';
import '../chat/chat_share.dart';
import '../map/live_sync_providers.dart';
import '../map/map_engine/geo.dart';
import '../map/trip_photos_screen.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../social/group_detail_screen.dart';
import '../social/invite_share.dart';
import '../social/social_providers.dart';
import '../social/user_profile_screen.dart';
import 'add_expense_screen.dart';
import '../map/pick_location_screen.dart';
import 'add_stop_screen.dart';
import 'plan_route_screen.dart';
import 'trip_checklist_tab.dart';
import 'trip_ledger.dart';
import 'trip_providers.dart';
import 'trip_recap_screen.dart';
import 'vehicle_mode_ui.dart';
import 'weather_ui.dart';

/// Trips whose start is currently in flight (guards against double taps).
final Set<String> _startingTrips = {};

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.trip});

  final Trip trip;

  Future<void> _startTrip(BuildContext context, WidgetRef ref) async {
    // A second tap while the first is in flight would hit the (now strict)
    // planned→active update and surface a bogus error.
    if (!_startingTrips.add(trip.id)) return;
    try {
      await ref.read(tripRepositoryProvider).startTrip(trip.id);
      // Directions are best-effort: the trip is already live either way.
      String? directionsError;
      if (trip.routePolyline == null) {
        directionsError = await _loadDirections(ref);
      }
      refreshTripData(ref, tripId: trip.id);
      if (!context.mounted) return;
      showAppToast(
        context,
        directionsError == null
            ? 'Trip started — your crew can follow you live.'
            : "Trip started, but directions couldn't load: $directionsError",
        error: directionsError != null,
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      _startingTrips.remove(trip.id);
    }
  }

  /// Plans and saves a route from the traveller's position to the trip's
  /// destination (or its last stop) so the map has directions to draw once the
  /// trip is live. Returns null on success, or a short reason it couldn't.
  Future<String?> _loadDirections(WidgetRef ref) async {
    try {
      final repo = ref.read(tripRepositoryProvider);
      var destinationName = trip.destinationName;
      var destination = trip.destinationPoint;
      if (destination == null) {
        final stops = await repo.stopsFor(trip.id);
        if (stops.isEmpty) return 'add a stop or destination first.';
        final last = stops.last;
        destinationName = last.name;
        destination = last.point;
      }

      final origin = trip.originPoint ?? await _currentPoint();
      if (origin == null) return 'location unavailable.';

      final routes = await GoogleMapsApiService.directions(
        origin: Geo.pos(origin.lat, origin.lng),
        destination: Geo.pos(destination.lat, destination.lng),
      );
      await repo.updateRoute(
        tripId: trip.id,
        originName: trip.originName ?? 'Start',
        originPoint: origin,
        destinationName: destinationName ?? 'Destination',
        destinationPoint: destination,
        routePolyline: routes.first.encodedPolyline,
      );
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  /// Re-plans the route on a planned or live trip. Before the trip starts the
  /// whole route can change; once it's live the new route starts from where the
  /// traveller is now (the trip's original origin is kept).
  Future<void> _replanRoute(BuildContext context, WidgetRef ref) async {
    final live = trip.status == TripStatus.active;
    final origin = trip.originPoint;
    final destination = trip.destinationPoint;
    final planned = await Navigator.of(context).push<PlannedRoute>(
      MaterialPageRoute(
        builder: (_) => PlanRouteScreen(
          title: 'Change route',
          initialOrigin: live || origin == null
              ? null
              : PickedLocation(
                  Geo.pos(origin.lat, origin.lng),
                  name: trip.originName,
                ),
          initialDestination: destination == null
              ? null
              : PickedLocation(
                  Geo.pos(destination.lat, destination.lng),
                  name: trip.destinationName,
                ),
        ),
      ),
    );
    if (planned == null || !context.mounted) return;
    try {
      final updated = await ref
          .read(tripRepositoryProvider)
          .updateRoute(
            tripId: trip.id,
            originName: live ? null : planned.originName,
            originPoint: live ? null : planned.originPoint,
            destinationName: planned.destinationName,
            destinationPoint: planned.destinationPoint,
            routePolyline: planned.routePolyline,
          );
      refreshTripData(ref, tripId: trip.id);
      if (!context.mounted) return;
      showAppToast(context, 'Route updated.');
      // This screen holds an immutable snapshot of the trip; swap in the
      // updated one so the map, stats and stops reflect the new route.
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TripDetailScreen(trip: updated)),
        ),
      );
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<LatLngPoint?> _currentPoint() async {
    try {
      final p =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 8),
            ),
          );
      return LatLngPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _completeTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Complete trip?',
      body: 'This finalizes your stats for the trip.',
      confirmLabel: 'Complete',
    );
    if (!confirmed) return;

    try {
      await ref.read(tripRepositoryProvider).completeTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
      ref.invalidate(tripStatsProvider(trip.id));
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Pauses a running trip. The screen pops for the same reason starting does:
  /// it was handed a snapshot of the trip, so leaving returns the user to the
  /// list/map, which re-reads the now-paused trip.
  Future<void> _pauseTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Pause trip?',
      body: 'Your crew stops seeing you live. You can resume it any time.',
      confirmLabel: 'Pause',
    );
    if (!confirmed) return;

    try {
      await ref.read(tripRepositoryProvider).pauseTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
      if (!context.mounted) return;
      showAppToast(context, 'Trip paused. Resume it whenever you are ready.');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _leaveTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Leave trip?',
      body: 'You will stop sharing your location on this trip.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).leaveTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _cancelTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Cancel trip?',
      body: 'This permanently deletes the trip, its stops and expenses for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tripRepositoryProvider).deleteTrip(trip.id);
      refreshTripData(ref, tripId: trip.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) => showAppConfirmDialog(
    context,
    title: title,
    message: body,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    bool isCreator,
  ) async {
    final canSaveRoute =
        trip.originPoint != null &&
        trip.destinationPoint != null &&
        trip.routePolyline != null;
    await showFSheet<void>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              BrandListRow(
                icon: Icons.auto_awesome_rounded,
                iconColor: BrandColors.primary,
                title: 'Trip recap',
                subtitle: 'The story of this drive — stats, spend, photos',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripRecapScreen(trip: trip),
                    ),
                  );
                },
              ),
              if (trip.status == TripStatus.planned ||
                  trip.status == TripStatus.active) ...[
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.alt_route_rounded,
                  iconColor: BrandColors.primary,
                  title: 'Change route',
                  subtitle: trip.status == TripStatus.active
                      ? 'Re-plan from where you are now'
                      : 'Pick a different origin, destination or route',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _replanRoute(context, ref);
                  },
                ),
              ],
              if (canSaveRoute) ...[
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.bookmark_add_outlined,
                  iconColor: BrandColors.primary,
                  title: 'Save route',
                  subtitle: 'Reuse this drive on a future trip',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _saveRouteTemplate(context, ref);
                  },
                ),
              ],
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.send_rounded,
                iconColor: BrandColors.primary,
                title: 'Send in chat',
                subtitle: 'Share this trip with a friend, group or trip chat',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showShareToSheet(
                    context,
                    ref,
                    title: 'Share trip',
                    share: ChatShare.trip(tripId: trip.id, title: trip.title),
                  );
                },
              ),
              if (isCreator) ...[
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.visibility_outlined,
                  iconColor: BrandColors.primary,
                  title: 'Share live link',
                  subtitle:
                      'Anyone can watch this trip live, no account needed',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _shareWatchLink(context, ref);
                  },
                ),
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.link_off_rounded,
                  title: 'Stop live link',
                  subtitle: 'Disable any links already shared',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _stopWatchLink(context, ref);
                  },
                ),
              ],
              const BrandRowDivider(),
              BrandListRow(
                icon: isCreator ? Icons.delete_outline : Icons.logout,
                titleColor: BrandColors.error,
                iconColor: BrandColors.error,
                iconBackground: BrandColors.errorContainer,
                title: isCreator ? 'Delete trip' : 'Leave trip',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (isCreator) {
                    _cancelTrip(context, ref);
                  } else {
                    _leaveTrip(context, ref);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Saves this trip's route to the user's personal template library so a
  /// familiar drive can be reused without re-planning.
  Future<void> _saveRouteTemplate(BuildContext context, WidgetRef ref) async {
    // Free accounts keep one saved route; Pro unlocks the library.
    if (!ref.read(isProProvider)) {
      final count = ref.read(routeTemplatesProvider).valueOrNull?.length ?? 0;
      if (count >= kFreeRouteTemplateLimit) {
        await showPaywall(context, feature: PremiumFeature.routeTemplates);
        return;
      }
    }
    final name = await showAppTextDialog(
      context,
      title: 'Save route',
      label: 'Name',
      hint: trip.destinationName ?? 'My route',
      confirmLabel: 'Save',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Route name');
    if (validationError != null) {
      if (context.mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref
          .read(routeTemplateRepositoryProvider)
          .createTemplate(
            name: name,
            originName: trip.originName,
            originPoint: trip.originPoint,
            destinationName: trip.destinationName,
            destinationPoint: trip.destinationPoint,
            routePolyline: trip.routePolyline,
          );
      ref.invalidate(routeTemplatesProvider);
      if (context.mounted) showAppToast(context, 'Route saved.');
    } catch (e) {
      if (!context.mounted) return;
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.routeTemplates);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    }
  }

  /// Creates (or reuses) this trip's public watch link and shares it.
  Future<void> _shareWatchLink(BuildContext context, WidgetRef ref) async {
    try {
      final token = await ref
          .read(tripRepositoryProvider)
          .ensureWatchLink(trip.id);
      ref.invalidate(tripWatchTokenProvider(trip.id));
      final base = Env.backendUrl.replaceAll(RegExp(r'/+$'), '');
      final url = '$base/watch/$token';
      await SharePlus.instance.share(
        ShareParams(
          subject: trip.title,
          text:
              'Follow "${trip.title}" live on Ranmap:\n$url\n'
              '(Anyone with this link can watch the crew on the road.)',
        ),
      );
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Disables the trip's watch links.
  Future<void> _stopWatchLink(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Stop live link?',
      message: 'Any shared link will stop working immediately.',
      confirmLabel: 'Stop',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(tripRepositoryProvider).revokeWatchLinks(trip.id);
      ref.invalidate(tripWatchTokenProvider(trip.id));
      if (context.mounted) showAppToast(context, 'Live link disabled.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCreator = SupabaseService.currentUser?.id == trip.createdBy;

    return BrandScaffold(
      header: BrandHeader(
        title: trip.title,
        onBack: () => Navigator.of(context).maybePop(),
        // A live trip is finished from the header, as a tick.
        actionIcon: trip.status == TripStatus.active
            ? Icons.check_rounded
            : null,
        actionTooltip: 'Complete trip',
        onAction: trip.status == TripStatus.active
            ? () => _completeTrip(context, ref)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.photo_library_outlined,
                semanticLabel: 'Trip photos',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TripPhotosScreen(
                      tripId: trip.id,
                      tripTitle: trip.title,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (trip.status == TripStatus.active) ...[
                _TripActionButton(
                  label: 'Pause',
                  onPressed: () => _pauseTrip(context, ref),
                ),
                const SizedBox(width: BrandSpace.sm),
              ] else if (trip.status == TripStatus.planned ||
                  trip.status == TripStatus.completed) ...[
                _TripActionButton(
                  label: trip.status == TripStatus.completed
                      ? 'Start again'
                      : trip.isPaused
                      ? 'Resume'
                      : 'Start',
                  onPressed: () => _startTrip(context, ref),
                ),
                const SizedBox(width: BrandSpace.sm),
              ],
              _HeaderIconButton(
                icon: Icons.more_vert,
                semanticLabel: 'More options',
                onTap: () => _showActions(context, ref, isCreator),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          Expanded(
            child: FTabs(
              expands: true,
              scrollable: true,
              children: [
                FTabEntry(
                  label: const Text('Stats'),
                  child: _StatsTab(
                    tripId: trip.id,
                    routePolyline: trip.routePolyline,
                    currency: trip.currency,
                  ),
                ),
                FTabEntry(
                  label: const Text('Stops'),
                  child: _StopsTab(
                    tripId: trip.id,
                    originPoint: trip.originPoint,
                  ),
                ),
                FTabEntry(
                  label: const Text('Crew'),
                  child: _CrewTab(
                    tripId: trip.id,
                    createdBy: trip.createdBy,
                    tripTitle: trip.title,
                    groupId: trip.groupId,
                  ),
                ),
                FTabEntry(
                  label: const Text('Expenses'),
                  child: _ExpensesTab(tripId: trip.id, currency: trip.currency),
                ),
                FTabEntry(
                  label: const Text('Pack'),
                  child: TripChecklistTab(tripId: trip.id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular header action used for the trip-level affordances that used to
/// live in the ForUI header's suffix slot.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Icon-only, so a screen reader needs this to announce the control.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 48,
          width: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BrandColors.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: BrandColors.textHeadline),
        ),
      ),
    );
  }
}

/// A header Start/Complete action that owns its own in-flight state, so a
/// double tap can't start or complete a trip twice.
class _TripActionButton extends StatefulWidget {
  const _TripActionButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_TripActionButton> createState() => _TripActionButtonState();
}

class _TripActionButtonState extends State<_TripActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandPrimaryButton(
      label: widget.label,
      trailingIcon: null,
      glow: false,
      expand: false,
      loading: _busy,
      onPressed: _busy ? null : _run,
    );
  }
}

class _StatsTab extends ConsumerWidget {
  const _StatsTab({
    required this.tripId,
    required this.currency,
    this.routePolyline,
  });

  final String tripId;

  /// ISO 4217 code the trip's expenses are denominated in — the fuel figures
  /// below label themselves with this rather than a hard-coded `$`.
  final String currency;
  final String? routePolyline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Full trip stats are marketed as a Pro feature (the paywall comparison and
    // the pricing page both say so), so a free account gets the upgrade prompt
    // rather than the live numbers.
    if (!ref.watch(isProProvider)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(BrandSpace.lg),
          child: BrandEmptyState(
            icon: Icons.workspace_premium_rounded,
            title: 'Trip stats are a Ranmap Pro feature.',
            message: 'Unlock live distance, speed, duration and fuel analysis for every trip.',
            tint: BrandColors.accentPeach,
            action: BrandPrimaryButton(
              label: 'Upgrade to Pro',
              trailingIcon: null,
              expand: false,
              onPressed: () =>
                  showPaywall(context, feature: PremiumFeature.history),
            ),
          ),
        ),
      );
    }
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final symbol = ledgerSymbol(currency);
    final statsAsync = ref.watch(tripStatsProvider(tripId));
    final expensesAsync = ref.watch(tripExpensesProvider(tripId));
    final speeds =
        ref.watch(tripSpeedProfileProvider(tripId)).valueOrNull ??
        const <double>[];

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(tripRepositoryProvider).recomputeStats(tripId);
        ref.invalidate(tripStatsProvider(tripId));
      },
      child: statsAsync.when(
        skipLoadingOnReload: true,
        data: (stats) {
          final s = stats ?? TripStats(tripId: tripId, userId: '');
          final fuelAvg = expensesAsync.valueOrNull == null
              ? null
              : _averageFuelCost(expensesAsync.valueOrNull!);
          final fuelCostPerKm = expensesAsync.valueOrNull == null
              ? null
              : _fuelCostPerKm(expensesAsync.valueOrNull!, s.totalDistanceKm);
          // Project the whole-route fuel cost from the planned polyline, when
          // both a route and a $/km rate are known.
          final projectedFuel = fuelCostPerKm == null
              ? null
              : _projectedFuelCost(fuelCostPerKm, routePolyline);
          // Litres / spend / efficiency, from the fuel-category rows only.
          final expenses = expensesAsync.valueOrNull;
          final fuelSummary = expenses == null
              ? null
              : _fuelSummary(expenses, s, unit, currency);

          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: BrandSpace.gutterSm,
                crossAxisSpacing: BrandSpace.gutterSm,
                childAspectRatio: 1.5,
                children: [
                  _StatTile(
                    label: 'Distance',
                    value: formatDistance(s.totalDistanceKm, unit),
                  ),
                  _StatTile(
                    label: 'Max speed',
                    value: formatSpeed(s.maxSpeedKmh, unit),
                  ),
                  _StatTile(
                    label: 'Avg speed',
                    value: formatSpeed(s.avgSpeedKmh, unit),
                  ),
                  _StatTile(
                    label: 'Duration',
                    value: _formatDuration(s.durationSeconds),
                  ),
                ],
              ),
              if (speeds.length >= 2) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _SpeedProfileCard(speeds: speeds, unit: unit),
              ],
              if (fuelAvg != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Avg fuel cost',
                  value: '$symbol${fuelAvg.toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              if (fuelCostPerKm != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Fuel cost / ${distanceUnitSymbol(unit)}',
                  value:
                      '$symbol${costPerDistance(fuelCostPerKm, unit).toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              if (projectedFuel != null) ...[
                const SizedBox(height: BrandSpace.gutterSm),
                _StatTile(
                  label: 'Est. fuel for route',
                  value: '$symbol${projectedFuel.toStringAsFixed(2)}',
                  wide: true,
                ),
              ],
              if (fuelSummary != null) ...[
                const SizedBox(height: BrandSpace.md),
                fuelSummary,
              ],
              const SizedBox(height: BrandSpace.md),
              Text(
                'Stats update automatically while the trip is active, or pull to refresh.',
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(tripStatsProvider(tripId)),
        ),
      ),
    );
  }

  double? _averageFuelCost(List<TripExpense> expenses) {
    final fuelExpenses = expenses.where((e) => e.category == 'fuel').toList();
    if (fuelExpenses.isEmpty) return null;
    final total = fuelExpenses.fold<double>(0, (sum, e) => sum + e.amount);
    return total / fuelExpenses.length;
  }

  /// Total fuel spend divided by distance actually travelled. Unlike the
  /// per-entry average above, this is a rate the user can extrapolate.
  double? _fuelCostPerKm(List<TripExpense> expenses, double distanceKm) {
    if (distanceKm <= 0) return null;
    final fuelTotal = expenses
        .where((e) => e.category == 'fuel')
        .fold<double>(0, (sum, e) => sum + e.amount);
    if (fuelTotal <= 0) return null;
    return fuelTotal / distanceKm;
  }

  /// Estimated fuel cost for the whole planned route, from its encoded
  /// polyline. Returns null when there's no route or it can't be decoded.
  double? _projectedFuelCost(double costPerKm, String? encodedPolyline) {
    if (encodedPolyline == null || encodedPolyline.isEmpty) return null;
    final points = GoogleMapsApiService.decodePolyline(encodedPolyline);
    if (points.length < 2) return null;
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += haversineMeters(
        points[i - 1].lat.toDouble(),
        points[i - 1].lng.toDouble(),
        points[i].lat.toDouble(),
        points[i].lng.toDouble(),
      );
    }
    if (meters <= 0) return null;
    return (meters / 1000) * costPerKm;
  }

  /// A fuel / efficiency block derived only from the fuel-category expense
  /// rows: total litres pumped, what it cost, and — when both a distance and
  /// some litres are known — the trip's efficiency. Returns null when there is
  /// no real reading to show, so the section is omitted entirely rather than
  /// printing zeros or placeholders.
  Widget? _fuelSummary(
    List<TripExpense> expenses,
    TripStats stats,
    DistanceUnit unit,
    String currency,
  ) {
    final fuel = expenses.where((e) => e.category == 'fuel').toList();
    if (fuel.isEmpty) return null;

    var litres = 0.0;
    var litresRecorded = false;
    var spend = 0.0;
    for (final e in fuel) {
      final l = e.fuelLiters;
      if (l != null) {
        litres += l;
        litresRecorded = true;
      }
      spend += e.amount;
    }

    final hasLitres = litresRecorded && litres > 0;
    final distanceKm = stats.totalDistanceKm;

    // Distance per litre in the user's unit, plus its inverse per 100 units.
    String? efficiencyValue;
    String? efficiencyCaption;
    if (hasLitres && distanceKm > 0) {
      final perLitre = distanceInUnit(distanceKm / litres, unit);
      final litresPer100 = litres / (distanceInUnit(distanceKm, unit) / 100);
      efficiencyValue =
          '${perLitre.toStringAsFixed(1)} ${distanceUnitSymbol(unit)}/L';
      efficiencyCaption =
          '${litresPer100.toStringAsFixed(1)} L/100 ${distanceUnitSymbol(unit)}';
    }

    final tiles = <Widget>[
      if (hasLitres)
        BrandStatTile(
          label: 'Fuel',
          value: '${litres.toStringAsFixed(1)} L',
          icon: Icons.local_gas_station_rounded,
        ),
      if (spend > 0)
        BrandStatTile(
          label: 'Fuel cost',
          value: '${ledgerSymbol(currency)}${spend.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
        ),
      if (efficiencyValue != null)
        BrandStatTile(
          label: 'Efficiency',
          value: efficiencyValue,
          caption: efficiencyCaption,
          icon: Icons.speed_rounded,
        ),
    ];
    if (tiles.isEmpty) return null;

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandSectionHeader(
            icon: Icons.local_gas_station_rounded,
            title: 'Fuel & efficiency',
          ),
          const SizedBox(height: BrandSpace.md),
          for (var i = 0; i < tiles.length; i += 2) ...[
            // Equal-height pairing, two tiles per row.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: BrandSpace.sm),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? tiles[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            if (i + 2 < tiles.length) const SizedBox(height: BrandSpace.sm),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.xs),
          Text(
            value,
            style: BrandText.weight(
              BrandText.headlineMd,
              800,
            ).copyWith(color: BrandColors.textHeadline),
          ),
        ],
      ),
    );
  }
}

class _StopsTab extends ConsumerStatefulWidget {
  const _StopsTab({required this.tripId, this.originPoint});

  final String tripId;

  /// The trip's planned origin, handed to [AddStopScreen] so the first stop's
  /// leg can be measured from it.
  final LatLngPoint? originPoint;

  @override
  ConsumerState<_StopsTab> createState() => _StopsTabState();
}

class _StopsTabState extends ConsumerState<_StopsTab> {
  /// Locally-reordered copy shown while a drag (and its save) is in flight,
  /// so the list doesn't snap back before the server round-trip completes.
  List<TripStop>? _optimisticOrder;

  /// Proposes a stop for the convoy to vote on, rather than adding it to the
  /// itinerary outright. Open to any participant (the RPC checks membership).
  Future<void> _proposeStop() async {
    final name = await showAppTextDialog(
      context,
      title: 'Propose a stop',
      label: 'Stop name',
      hint: 'Fuel + coffee',
      confirmLabel: 'Propose',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Stop name');
    if (validationError != null) {
      if (mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref
          .read(tripRepositoryProvider)
          .proposeStop(tripId: widget.tripId, name: name);
      ref.invalidate(tripProposalsProvider(widget.tripId));
      if (mounted) showAppToast(context, 'Proposed — the crew will vote.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _onReorder(
    List<TripStop> stops,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<TripStop>.of(stops);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _optimisticOrder = reordered);

    try {
      await ref
          .read(tripRepositoryProvider)
          .reorderStops(
            tripId: widget.tripId,
            orderedStopIds: reordered.map((s) => s.id).toList(),
          );
      // The new order is persisted — resync the legs so each describes the
      // segment it now does. Best-effort: a resync failure must not undo the
      // saved order, so it never surfaces as a reorder error.
      try {
        await _resyncLegs(reordered);
      } catch (e) {
        debugPrint('reorder: leg resync failed: $e');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      ref.invalidate(tripStopsProvider(widget.tripId));
      ref.invalidate(tripLegsProvider(widget.tripId));
      if (mounted) setState(() => _optimisticOrder = null);
    }
  }

  /// The default travel mode for a leg with no recorded mode: the current
  /// user's profile vehicle, or the DB default when no profile is loaded.
  String get _defaultLegMode =>
      ref.read(myProfileProvider).valueOrNull?.vehicleType ??
      kDefaultVehicleType;

  /// Rewrites the trip's legs to match [orderedStops] (the new waypoint order:
  /// origin → stop0 → stop1 → …), re-measuring each segment.
  ///
  /// Each leg's travel mode is preserved from the leg that already arrived at
  /// the same stop (keyed by `to_stop_id`, snapshotted before the legs are
  /// touched); a stop with no prior leg falls back to [_defaultLegMode]. Because
  /// the segment changed, the old geometry is stale, so every leg is
  /// re-measured through the directions service — a leg whose measurement fails
  /// (or whose route is unknown) is still stored, with its mode and a null
  /// measurement, never an invented one.
  ///
  /// Deleting every leg first and recreating them sidesteps the
  /// `unique (trip_id, seq)` constraint that renumbering in place would hit.
  Future<void> _resyncLegs(List<TripStop> orderedStops) async {
    // Nothing to route when the trip has no stops.
    if (orderedStops.isEmpty) return;
    final repo = ref.read(tripRepositoryProvider);
    final defaultMode = _defaultLegMode;

    // Snapshot each leg's mode by the stop it arrives at, before the delete
    // below wipes them.
    final existingLegs =
        ref.read(tripLegsProvider(widget.tripId)).valueOrNull ??
        await repo.fetchTripLegs(widget.tripId);
    final modeByStop = <String, String>{
      for (final leg in existingLegs)
        if (leg.toStopId != null) leg.toStopId!: leg.mode,
    };

    await repo.deleteTripLegs(widget.tripId);

    for (var i = 0; i < orderedStops.length; i++) {
      final stop = orderedStops[i];
      final mode = modeByStop[stop.id] ?? defaultMode;
      // The waypoint this leg leaves from: the trip origin for the first stop,
      // otherwise the stop just before it. Null when the trip has no origin —
      // the leg is then recorded with its mode and no measurement.
      final previousPoint = i == 0
          ? widget.originPoint
          : orderedStops[i - 1].point;

      double? distanceM;
      double? durationS;
      String? polyline;
      if (previousPoint != null) {
        try {
          final routes = await GoogleMapsApiService.directions(
            origin: Geo.pos(previousPoint.lat, previousPoint.lng),
            destination: Geo.pos(stop.point.lat, stop.point.lng),
            profile: mode,
          );
          if (routes.isNotEmpty) {
            final route = routes.first;
            distanceM = route.distanceMeters.toDouble();
            durationS = route.durationSeconds.toDouble();
            polyline = route.encodedPolyline;
          }
        } catch (_) {
          // Segment changed but couldn't be re-measured — keep the mode and
          // leave the measurement null rather than reuse stale geometry.
        }
      }

      await repo.createTripLeg(
        tripId: widget.tripId,
        seq: i,
        toStopId: stop.id,
        mode: mode,
        distanceM: distanceM,
        durationS: durationS,
        polyline: polyline,
      );
    }
  }

  /// The "Convoy vote" cards for the trip's still-open proposals (none when
  /// there's nothing to vote on, so the section disappears entirely).
  List<Widget> _convoyVoteCards(List<StopProposal> proposals) {
    return [
      for (var i = 0; i < proposals.length; i++) ...[
        if (i > 0) const SizedBox(height: BrandSpace.gutterSm),
        _ConvoyVoteCard(
          key: ValueKey(proposals[i].id),
          tripId: widget.tripId,
          proposal: proposals[i],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = ref.watch(tripStopsProvider(widget.tripId));
    // Each leg is keyed by the stop it arrives at (its `to_stop_id`), so the leg
    // leading into a stop can be shown just above it and follows that stop when
    // the itinerary is reordered. Segments with no leg are left blank rather
    // than given an invented one.
    final legs =
        ref.watch(tripLegsProvider(widget.tripId)).valueOrNull ??
        const <TripLeg>[];
    final legByStopId = {
      for (final leg in legs)
        if (leg.toStopId != null) leg.toStopId!: leg,
    };
    // Only open proposals are shown; a promoted/rejected one leaves the vote
    // card and (on promotion) shows up in the itinerary below.
    final openProposals =
        ref
            .watch(tripProposalsProvider(widget.tripId))
            .valueOrNull
            ?.where((p) => p.isOpen)
            .toList() ??
        const <StopProposal>[];

    return Stack(
      children: [
        PullToRefresh(
          onRefresh: () => ref.refresh(tripStopsProvider(widget.tripId).future),
          child: stopsAsync.when(
            skipLoadingOnReload: true,
            data: (fetched) {
              final voteCards = _convoyVoteCards(openProposals);
              if (fetched.isEmpty) {
                // Nothing to reorder yet — still surface any open votes.
                if (voteCards.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: BrandEmptyState(
                        imageAsset:
                            'assets/images/onboarding/welcome_pitstop.jpg',
                        icon: Icons.place_rounded,
                        title: 'Map your route stops',
                        message: 'Add scenic overlooks, coffee spots, and fuel stops. Your convoy will vote on stops and sync route ETAs in real-time.',
                      ),
                    ),
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    top: BrandSpace.md,
                    bottom: BrandSpace.xl,
                  ),
                  children: [
                    ...voteCards,
                    const SizedBox(height: BrandSpace.xl),
                    const BrandEmptyState(
                      imageAsset:
                          'assets/images/onboarding/welcome_pitstop.jpg',
                      icon: Icons.place_rounded,
                      title: 'Map your route stops',
                      message: 'Add scenic overlooks, coffee spots, and fuel stops. Your convoy will vote on stops and sync route ETAs in real-time.',
                    ),
                  ],
                );
              }
              final stops = _optimisticOrder ?? fetched;
              TripStop? nextStop;
              for (final s in stops) {
                if (s.actualArrival == null) {
                  nextStop = s;
                  break;
                }
              }
              return Column(
                children: [
                  if (nextStop != null)
                    _NextStopEta(tripId: widget.tripId, stop: nextStop),
                  _StopWeatherCard(tripId: widget.tripId),
                  if (voteCards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BrandSpace.md,
                        BrandSpace.md,
                        BrandSpace.md,
                        0,
                      ),
                      child: Column(children: voteCards),
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(
                        top: BrandSpace.md,
                        bottom: BrandSpace.xl,
                      ),
                      itemCount: stops.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _onReorder(stops, oldIndex, newIndex),
                      itemBuilder: (context, i) {
                        final stop = stops[i];
                        // Arrived stops are done; the first not-yet-arrived stop is
                        // the one you're heading to; the rest are upcoming.
                        final state = stop.actualArrival != null
                            ? BrandTimelineState.done
                            : identical(stop, nextStop)
                            ? BrandTimelineState.active
                            : BrandTimelineState.upcoming;
                        // The leg that arrives at this stop, when one was
                        // recorded.
                        final leg = legByStopId[stop.id];
                        return BrandTimelineRow(
                          key: ValueKey(stop.id),
                          state: state,
                          isLast: i == stops.length - 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (leg != null) ...[
                                _LegIndicator(leg: leg),
                                const SizedBox(height: BrandSpace.sm),
                              ],
                              Dismissible(
                                key: ValueKey('dismiss-${stop.id}'),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) => _confirmDeleteDialog(
                                  context,
                                  'Delete stop?',
                                ),
                                onDismissed: (_) async {
                                  // The chain that remains once this stop is gone,
                                  // used to resync the survivors' legs below.
                                  final remaining = stops
                                      .where((s) => s.id != stop.id)
                                      .toList();
                                  try {
                                    await ref
                                        .read(tripRepositoryProvider)
                                        .deleteStop(stop.id);
                                  } catch (_) {
                                    // Fall through to refresh the list below.
                                  } finally {
                                    // Refresh the itinerary straight away so the
                                    // dismissed row doesn't linger while the (slower)
                                    // leg resync below runs.
                                    ref.invalidate(
                                      tripStopsProvider(widget.tripId),
                                    );
                                  }
                                  // Deleting the stop cascades its own leg away
                                  // (0016_trip_legs.sql); resync the rest so each
                                  // surviving leg describes its (now different)
                                  // segment and the chain keeps a contiguous seq.
                                  // Best-effort: the delete is already done, so a
                                  // resync failure must not fail the dismissal.
                                  if (remaining.isNotEmpty) {
                                    try {
                                      await _resyncLegs(remaining);
                                    } catch (e) {
                                      debugPrint(
                                        'deleteStop: leg resync failed: $e',
                                      );
                                    }
                                  }
                                  ref.invalidate(
                                    tripLegsProvider(widget.tripId),
                                  );
                                },
                                background: _dismissBackground(),
                                child: _StopCard(stop: stop),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(tripStopsProvider(widget.tripId)),
            ),
          ),
        ),
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandFab(
                primary: false,
                icon: Icons.how_to_vote_outlined,
                tooltip: 'Propose a stop',
                onPressed: _proposeStop,
              ),
              const SizedBox(width: BrandSpace.sm),
              BrandFab(
                icon: Icons.add_location_alt_rounded,
                tooltip: 'Add stop',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddStopScreen(
                        tripId: widget.tripId,
                        originPoint: widget.originPoint,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The travel-mode connector shown just above the stop a leg arrives at: the
/// leg's mode as a brand pill, with its real measured distance/duration
/// alongside. A leg with no measurement shows only its mode — never an
/// invented figure.
class _LegIndicator extends ConsumerWidget {
  const _LegIndicator({required this.leg});

  final TripLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final distance = leg.distanceM;
    final duration = leg.durationS;
    final measurement = [
      if (distance != null) formatDistance(distance / 1000, unit),
      if (duration != null) _formatLegDuration(duration),
    ].join(' · ');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandPill(
          label: vehicleModeLabel(leg.mode),
          icon: vehicleModeIcon(leg.mode),
          background: BrandColors.surfaceContainerLow,
          foreground: BrandColors.onSurfaceVariant,
          iconColor: BrandColors.primary,
        ),
        if (measurement.isNotEmpty) ...[
          const SizedBox(width: BrandSpace.sm),
          Text(
            measurement,
            style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// A leg's routed duration as `~N min` (or `~H h M min` past an hour) — the
/// `~` marks it as a routing estimate, not a planned arrival time.
String _formatLegDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '~$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '~$hours h' : '~$hours h $remainder min';
}

/// A single open convoy vote: the proposed stop, the real approval tally and
/// progress toward a majority, and the caller's Approve / Reject actions. All
/// counts come from the server (see the `trip_proposals` RPC) — nothing is
/// tallied on the client.
class _ConvoyVoteCard extends ConsumerStatefulWidget {
  const _ConvoyVoteCard({
    super.key,
    required this.tripId,
    required this.proposal,
  });

  final String tripId;
  final StopProposal proposal;

  @override
  ConsumerState<_ConvoyVoteCard> createState() => _ConvoyVoteCardState();
}

class _ConvoyVoteCardState extends ConsumerState<_ConvoyVoteCard> {
  bool _voting = false;

  Future<void> _vote(bool approve) async {
    setState(() => _voting = true);
    try {
      await ref
          .read(tripRepositoryProvider)
          .voteStopProposal(widget.proposal.id, approve);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      // Refresh the tally, and the itinerary too — an approval that crosses the
      // majority promotes the proposal into a real stop.
      ref.invalidate(tripProposalsProvider(widget.tripId));
      ref.invalidate(tripStopsProvider(widget.tripId));
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    final hasVoted = p.myVote != null;

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandSectionHeader(
            icon: Icons.how_to_vote_rounded,
            title: 'Convoy vote',
            subtitle: p.name,
            trailing: BrandPill(
              label: hasVoted
                  ? (p.myVote! ? 'You approved' : 'You rejected')
                  : 'Vote now',
              icon: hasVoted
                  ? Icons.check_circle_rounded
                  : Icons.ballot_rounded,
              background: BrandColors.surfaceContainerLow,
              foreground: BrandColors.onSurfaceVariant,
              iconColor: p.myVote == false ? BrandColors.error : null,
            ),
          ),
          if (p.note != null) ...[
            const SizedBox(height: BrandSpace.sm),
            Text(
              p.note!,
              style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
            ),
          ],
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              Text(
                '${p.approvals} of ${p.memberCount} approved',
                style: BrandText.weight(
                  BrandText.labelMd,
                  700,
                ).copyWith(color: BrandColors.textHeadline),
              ),
              const Spacer(),
              if (p.rejections > 0)
                Text(
                  '${p.rejections} rejected',
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandProgressBar(value: p.approvalFraction),
          const SizedBox(height: BrandSpace.md),
          Row(
            children: [
              Expanded(
                child: BrandPrimaryButton(
                  label: 'Approve',
                  leadingIcon: Icons.thumb_up_rounded,
                  trailingIcon: null,
                  glow: false,
                  loading: _voting,
                  onPressed: _voting ? null : () => _vote(true),
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Reject',
                  leading: Icon(
                    Icons.thumb_down_rounded,
                    size: 18,
                    color: BrandColors.textHeadlineAlt,
                  ),
                  onPressed: _voting ? null : () => _vote(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A one-line "next stop" banner: distance from the device's live position
/// and an ETA from the trip's average speed. Hidden until a position and a
/// prior average are both available.
class _NextStopEta extends ConsumerWidget {
  const _NextStopEta({required this.tripId, required this.stop});

  final String tripId;
  final TripStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final position = ref.watch(devicePositionProvider).valueOrNull;
    if (position == null) return const SizedBox.shrink();

    final km =
        haversineMeters(
          position.latitude,
          position.longitude,
          stop.point.lat,
          stop.point.lng,
        ) /
        1000;
    final avgKmh =
        ref.watch(tripStatsProvider(tripId)).valueOrNull?.avgSpeedKmh ?? 0;

    final eta = avgKmh > 1 ? '~${((km / avgKmh) * 60).round()} min' : '—';

    return Material(
      color: BrandColors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BrandSpace.md,
          BrandSpace.gutterSm,
          BrandSpace.md,
          BrandSpace.gutterSm,
        ),
        child: Row(
          children: [
            Icon(Icons.flag_rounded, color: BrandColors.primary),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Text(
                'Next: ${stop.name}',
                overflow: TextOverflow.ellipsis,
                style: BrandText.weight(
                  BrandText.titleSm,
                  700,
                ).copyWith(color: BrandColors.textHeadline),
              ),
            ),
            Text(
              '${formatDistance(km, unit)} · $eta',
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop});

  final TripStop stop;

  IconData get _icon {
    switch (stop.kind) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'scenery':
        return Icons.landscape_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'rest':
        return Icons.hotel_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.gutterSm,
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: BrandColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: BrandColors.primary, size: 20),
          ),
          const SizedBox(width: BrandSpace.gutterSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: BrandText.weight(
                    BrandText.titleSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
                if (stop.plannedArrival != null)
                  Text(
                    'ETA ${DateFormat.yMMMd().add_jm().format(stop.plannedArrival!.toLocal())}',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                if (stop.notes != null)
                  Text(
                    stop.notes!,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textBody,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.drag_handle_rounded, color: BrandColors.textMuted),
        ],
      ),
    );
  }
}

/// The trip's crew: everyone invited or on board, plus affordances to invite
/// someone *after* the trip exists (not only at creation time) and to copy an
/// invite for someone who isn't a Ranmap user yet.
class _CrewTab extends ConsumerWidget {
  const _CrewTab({
    required this.tripId,
    required this.createdBy,
    required this.tripTitle,
    this.groupId,
  });

  final String tripId;
  final String createdBy;
  final String tripTitle;

  /// The group this trip belongs to, when it was planned for one. Null for a
  /// standalone trip.
  final String? groupId;

  Future<void> _shareInvite(BuildContext context, WidgetRef ref) async {
    // The shared helper always includes the invite link (falling back to the
    // app's custom scheme until the production domain is live), so the
    // "Send a link" promise is actually kept.
    await shareMyInviteLink(
      context,
      ref,
      intro: 'Join me on Ranmap for "$tripTitle".',
    );
  }

  Future<void> _addMember(
    BuildContext context,
    List<Map<String, dynamic>> members,
  ) {
    final existing = <String>{
      for (final m in members)
        (m['profiles'] as Map<String, dynamic>?)?['username'] as String? ?? '',
    };
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      builder: (_) =>
          _AddMemberSheet(tripId: tripId, existingUsernames: existing),
    );
  }

  /// Removes a member (or cancels a pending invite). Only shown to the trip's
  /// creator — RLS permits the creator (or the member themselves) to delete.
  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> member,
  ) async {
    final username =
        (member['profiles'] as Map<String, dynamic>?)?['username'] as String? ??
        'this member';
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Remove from trip?',
      message: 'Remove @$username from this trip?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(tripRepositoryProvider)
          .removeMember(tripId: tripId, userId: member['user_id'] as String);
      ref.invalidate(tripMembersProvider(tripId));
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(tripMembersProvider(tripId));
    final members = membersAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final myUid = SupabaseService.currentUser?.id;
    final isCreator = myUid != null && myUid == createdBy;

    return Stack(
      children: [
        membersAsync.when(
          skipLoadingOnReload: true,
          data: (fetched) {
            // Accepted members first; pending invites trail.
            final sorted = [...fetched]
              ..sort((a, b) {
                final aAccepted = a['invite_status'] == 'accepted' ? 0 : 1;
                final bAccepted = b['invite_status'] == 'accepted' ? 0 : 1;
                return aAccepted.compareTo(bAccepted);
              });
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(tripMembersProvider(tripId)),
              child: ListView(
                padding: const EdgeInsets.only(top: BrandSpace.md, bottom: 96),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: BrandListRow(
                      icon: Icons.ios_share_rounded,
                      iconColor: BrandColors.primary,
                      title: 'Share invite',
                      subtitle: 'Send a link so they can add you as a friend',
                      onTap: () => _shareInvite(context, ref),
                    ),
                  ),
                  if (groupId != null) ...[
                    const SizedBox(height: BrandSpace.md),
                    _TripGroupCard(groupId: groupId!),
                  ],
                  const SizedBox(height: BrandSpace.md),
                  if (sorted.isEmpty)
                    const BrandEmptyState(
                      imageAsset:
                          'assets/images/scenic/friends_crew_scenic.jpg',
                      icon: Icons.groups_rounded,
                      title: 'Invite your convoy crew',
                      message: 'Share an invite link so your friends can track the live map, broadcast GPS, and talk hands-free.',
                    )
                  else ...[
                    BrandSectionHeader(
                      icon: Icons.groups_rounded,
                      title: 'Crew',
                      trailing: BrandPill(label: '${sorted.length}'),
                    ),
                    const SizedBox(height: BrandSpace.sm),
                    BrandCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BrandSpace.md,
                        vertical: BrandSpace.xs,
                      ),
                      child: Column(
                        children: [
                          for (final member in sorted)
                            _CrewMemberRow(
                              member: member,
                              isOrganizer: member['user_id'] == createdBy,
                              // Never offer to remove the organizer: dropping
                              // the creator's own membership would orphan the
                              // trip.
                              onRemove:
                                  isCreator && member['user_id'] != createdBy
                                  ? () => _removeMember(context, ref, member)
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(tripMembersProvider(tripId)),
          ),
        ),
        // Only the trip's creator may add members (RLS enforces it too).
        if (isCreator)
          Positioned(
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandPrimaryButton(
              label: 'Add member',
              leadingIcon: Icons.person_add_alt_1_rounded,
              trailingIcon: null,
              expand: false,
              onPressed: () => _addMember(context, members),
            ),
          ),
      ],
    );
  }
}

/// Links a trip back to the group it was planned for (when it has one).
class _TripGroupCard extends ConsumerWidget {
  const _TripGroupCard({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    if (group == null) return const SizedBox.shrink();
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: BrandListRow(
        icon: Icons.groups_rounded,
        iconColor: BrandColors.primary,
        title: group.name,
        subtitle: 'Group this trip belongs to',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
        ),
      ),
    );
  }
}

/// One row in a crew roster: a member's real avatar, their handle, and either
/// their invite status or a caller-supplied trailing action.
class _CrewMemberRow extends StatelessWidget {
  const _CrewMemberRow({
    required this.member,
    this.isOrganizer = false,
    this.trailing,
    this.onTap,
    this.onRemove,
  });

  final Map<String, dynamic> member;
  final bool isOrganizer;

  /// Overrides the status pill (e.g. an "add" glyph in the friend picker).
  final Widget? trailing;
  final VoidCallback? onTap;

  /// When set, a remove affordance is shown (for the trip creator).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final username = profile?['username'] as String? ?? 'member';
    final seed = profile?['avatar_id'] as String? ?? kDefaultAvatarSeed;
    final accepted = member['invite_status'] == 'accepted';

    final Widget status =
        trailing ??
        (isOrganizer
            ? const BrandPill(label: 'Organizer', bold: true)
            : accepted
            ? const BrandPill(
                label: 'Going',
                icon: Icons.check_rounded,
                bold: true,
              )
            : const BrandPill(
                label: 'Invited',
                icon: Icons.hourglass_empty_rounded,
              ));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: member['user_id'] is String
                  ? () => openUserProfile(context, member['user_id'] as String)
                  : null,
              child: AvatarView(
                seed: seed,
                size: 40,
                background: BrandColors.surfaceContainerLow,
                accentColor: BrandColors.primary,
              ),
            ),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.titleSm.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
            ),
            const SizedBox(width: BrandSpace.sm),
            status,
            if (onRemove != null) ...[
              const SizedBox(width: BrandSpace.xs),
              GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: BrandColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "add to crew" sheet: invite by exact username, or tap a friend. Each
/// invite fires immediately so the roster behind the sheet updates.
class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({
    required this.tripId,
    required this.existingUsernames,
  });

  final String tripId;
  final Set<String> existingUsernames;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _ctrl = TextEditingController();
  final Set<String> _invited = {};
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isOnTrip(String username) =>
      widget.existingUsernames.contains(username) ||
      _invited.contains(username);

  Future<void> _invite(String raw) async {
    final username = raw.trim();
    if (username.isEmpty || _busy) return;
    if (_isOnTrip(username)) {
      showAppToast(context, '@$username is already in your crew.');
      return;
    }

    setState(() => _busy = true);
    try {
      final invited = await ref
          .read(tripRepositoryProvider)
          .inviteByUsername(tripId: widget.tripId, username: username);
      if (!invited) {
        if (mounted) {
          showAppToast(
            context,
            'No user found with username "$username".',
            error: true,
          );
        }
        return;
      }
      ref.invalidate(tripMembersProvider(widget.tripId));
      if (!mounted) return;
      setState(() {
        _invited.add(username);
        _ctrl.clear();
      });
      showAppToast(context, '@$username invited.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return BrandSheetSurface(
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Add to crew',
            style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.xs),
          Text(
            'Everyone you add can follow the trip on the live map.',
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: BrandTextField(
                  controller: _ctrl,
                  hint: 'theirname',
                  onSubmitted: _invite,
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              BrandPrimaryButton(
                label: 'Add',
                trailingIcon: null,
                glow: false,
                expand: false,
                loading: _busy,
                onPressed: _busy ? null : () => _invite(_ctrl.text),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          friendsAsync.when(
            skipLoadingOnReload: true,
            data: (rows) {
              final myUid = SupabaseService.currentUser?.id;
              final friends = rows
                  .map((row) {
                    final isRequester = row['requester_id'] == myUid;
                    return (isRequester ? row['addressee'] : row['requester'])
                        as Map<String, dynamic>?;
                  })
                  .whereType<Map<String, dynamic>>()
                  .where((p) => !_isOnTrip(p['username'] as String? ?? ''))
                  .toList();

              if (friends.isEmpty) {
                return Text(
                  'No more friends to add here — share an invite for anyone '
                  'else.',
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'From your friends',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.textBody,
                    ),
                  ),
                  const SizedBox(height: BrandSpace.xs),
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final profile in friends)
                          _CrewMemberRow(
                            member: {
                              'invite_status': 'invited',
                              'profiles': profile,
                            },
                            trailing: Icon(
                              Icons.add_circle_outline_rounded,
                              size: 22,
                              color: BrandColors.primary,
                            ),
                            onTap: () =>
                                _invite(profile['username'] as String? ?? ''),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: BrandSpace.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              "Couldn't load your friends.",
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.tripId, required this.currency});

  final String tripId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(tripExpensesProvider(tripId));

    return Stack(
      children: [
        PullToRefresh(
          onRefresh: () => ref.refresh(tripExpensesProvider(tripId).future),
          child: expensesAsync.when(
            skipLoadingOnReload: true,
            data: (expenses) {
              if (expenses.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: BrandEmptyState(
                      imageAsset:
                          'assets/images/scenic/passport_journal_scenic.jpg',
                      icon: Icons.receipt_long_rounded,
                      title: 'Shared Trip Ledger',
                      message: 'Log fuel, park passes, tolls, and coffee. RanMap automatically balances the math and settles up evenly.',
                    ),
                  ),
                );
              }

              final total = expenses.fold<double>(
                0,
                (sum, e) => sum + e.amount,
              );
              final byCategory = <String, double>{};
              for (final e in expenses) {
                byCategory[e.category] =
                    (byCategory[e.category] ?? 0) + e.amount;
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(
                  top: BrandSpace.md,
                  bottom: BrandSpace.xl,
                ),
                children: [
                  _LedgerSummary(
                    tripId: tripId,
                    expenses: expenses,
                    total: total,
                    byCategory: byCategory,
                    currency: currency,
                  ),
                  const SizedBox(height: BrandSpace.md),
                  ...expenses.map(
                    (e) => Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) =>
                          _confirmDeleteDialog(context, 'Delete expense?'),
                      onDismissed: (_) async {
                        try {
                          await ref
                              .read(tripRepositoryProvider)
                              .deleteExpense(e.id);
                          ref.invalidate(tripExpensesProvider(tripId));
                        } catch (_) {
                          ref.invalidate(tripExpensesProvider(tripId));
                        }
                      },
                      background: _dismissBackground(),
                      child: _ExpenseCard(expense: e, currency: currency),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(tripExpensesProvider(tripId)),
            ),
          ),
        ),
        Positioned(
          right: BrandSpace.md,
          bottom: BrandSpace.md,
          child: BrandPrimaryButton(
            label: 'Log expense',
            leadingIcon: Icons.add_rounded,
            trailingIcon: null,
            expand: false,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AddExpenseScreen(tripId: tripId, currency: currency),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The trip's spend ledger: total, category split, and an equal-share
/// settlement computed from what each member actually paid. All real data.
class _LedgerSummary extends ConsumerWidget {
  const _LedgerSummary({
    required this.tripId,
    required this.expenses,
    required this.total,
    required this.byCategory,
    required this.currency,
  });

  final String tripId;
  final List<TripExpense> expenses;
  final double total;
  final Map<String, double> byCategory;

  /// The trip's currency — a deliberate single source rather than one
  /// arbitrary expense row's [TripExpense.currency].
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ledgerSymbol(currency);

    // Only accepted members share costs: someone merely invited (who may never
    // join) must not appear as a payer, or every balance and settlement step
    // would be wrong. Members who logged an expense are still included below
    // via `expenses`, so a payer who later left the trip isn't dropped.
    final members =
        (ref.watch(tripMembersProvider(tripId)).valueOrNull ??
                const <Map<String, dynamic>>[])
            .where((m) => m['invite_status'] == 'accepted')
            .toList();
    final nameById = <String, String>{
      for (final m in members)
        (m['user_id'] as String):
            (m['profiles'] as Map<String, dynamic>?)?['username'] as String? ??
            'member',
    };
    final ids = <String>{...nameById.keys, ...expenses.map((e) => e.userId)};
    final paidBy = <String, double>{};
    for (final e in expenses) {
      paidBy[e.userId] = (paidBy[e.userId] ?? 0) + e.amount;
    }
    final balances = ledgersBalances(
      paidBy: paidBy,
      memberIds: ids,
      total: total,
    );
    final transfers = settleLedger(balances);
    String name(String id) => nameById[id] ?? 'member';
    // Scale for the per-member diverging bars, so the biggest swing fills its
    // half and everyone else is read against it.
    final maxAbs = balances.values.fold<double>(
      0,
      (m, v) => v.abs() > m ? v.abs() : m,
    );

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: 20,
                color: BrandColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Trip ledger',
                style: BrandText.titleSm.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.md),
          Text(
            'Total spent',
            style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
          ),
          Text(
            '$symbol${total.toStringAsFixed(2)}',
            style: BrandText.displayLgMobile.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          const SizedBox(height: BrandSpace.sm),
          if (byCategory.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.xs),
            Text(
              'By category',
              style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
            ),
            const SizedBox(height: BrandSpace.sm),
            // Largest category first, each bar scaled against it so the split
            // reads at a glance rather than as a row of equally-weighted pills.
            Builder(
              builder: (context) {
                final sorted = byCategory.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final maxCat = sorted.first.value;
                return Column(
                  children: [
                    for (final (i, e) in sorted.indexed) ...[
                      if (i > 0) const SizedBox(height: BrandSpace.sm),
                      BrandBreakdownRow(
                        label: ledgerCategoryLabel(e.key),
                        fraction: maxCat <= 0 ? 0 : e.value / maxCat,
                        valueLabel: '$symbol${e.value.toStringAsFixed(2)}',
                        color: _ledgerCategoryColor(e.key),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: BrandSpace.md),
          Divider(height: 1, color: BrandColors.hairline),
          const SizedBox(height: BrandSpace.md),
          Text(
            'Split evenly · ${ids.length} ${ids.length == 1 ? 'person' : 'people'}',
            style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.sm),
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '@${name(id)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.bodySm.copyWith(
                            color: BrandColors.textHeadline,
                          ),
                        ),
                      ),
                      Text(
                        balances[id]! >= 0
                            ? 'gets back $symbol${balances[id]!.toStringAsFixed(2)}'
                            : 'owes $symbol${(-balances[id]!).toStringAsFixed(2)}',
                        style: BrandText.labelSm.copyWith(
                          color: balances[id]! >= 0
                              ? BrandColors.primary
                              : BrandColors.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Owed extends left, credited right, centred on zero.
                  BrandDivergingBar(value: balances[id]!, maxAbs: maxAbs),
                ],
              ),
            ),
          const SizedBox(height: BrandSpace.xs),
          if (transfers.isEmpty)
            Text(
              'All square.',
              style: BrandText.bodySm.copyWith(color: BrandColors.primary),
            )
          else ...[
            Divider(height: 1, color: BrandColors.hairline),
            const SizedBox(height: BrandSpace.md),
            Text(
              'Settle up',
              style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
            ),
            const SizedBox(height: BrandSpace.sm),
            for (final t in transfers)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '@${name(t.from)} → @${name(t.to)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.bodySm.copyWith(
                          color: BrandColors.textHeadline,
                        ),
                      ),
                    ),
                    Text(
                      '$symbol${t.amount.toStringAsFixed(2)}',
                      style: BrandText.weight(
                        BrandText.labelSm,
                        700,
                      ).copyWith(color: BrandColors.primary),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense, required this.currency});

  final TripExpense expense;

  /// The trip's currency, so the row labels itself with the right symbol.
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BrandSpace.gutterSm),
      child: BrandCard(
        radius: BrandRadii.cardRadius,
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpace.md,
          vertical: BrandSpace.gutterSm,
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                color: BrandColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: BrandSpace.gutterSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ledgerSymbol(currency)}${expense.amount.toStringAsFixed(2)} · ${expense.category}',
                    style: BrandText.weight(
                      BrandText.titleSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  if (expense.note != null)
                    Text(
                      expense.note!,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A speed-over-time profile for the current user's trip pings: an area
/// sparkline of the recorded samples with max and average captions in the
/// user's unit. Built only when there are at least two samples.
class _SpeedProfileCard extends StatelessWidget {
  const _SpeedProfileCard({required this.speeds, required this.unit});

  /// Recorded speeds in km/h, in time order.
  final List<double> speeds;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final maxKmh = speeds.reduce((a, b) => a > b ? a : b);
    final avgKmh = speeds.reduce((a, b) => a + b) / speeds.length;
    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandSectionHeader(
            icon: Icons.speed_rounded,
            title: 'Speed profile',
          ),
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Max ${formatSpeed(maxKmh, unit)}',
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
              ),
              Text(
                'Avg ${formatSpeed(avgKmh, unit)}',
                style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandSparkline(values: speeds, width: double.infinity, height: 72),
          const SizedBox(height: BrandSpace.xs),
          Text(
            'Speed across the trip, from your recorded pings.',
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Weather at each upcoming stop, for its planned arrival time. Hidden until
/// at least one stop has both a planned time and a forecast.
class _StopWeatherCard extends ConsumerWidget {
  const _StopWeatherCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops =
        ref.watch(tripStopsProvider(tripId)).valueOrNull ?? const <TripStop>[];

    // Weather en route is a Ranmap Pro feature. Free users get a compact
    // upgrade teaser when they actually have a timed stop to forecast.
    if (!ref.watch(isProProvider)) {
      if (!stops.any((s) => s.plannedArrival != null)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          BrandSpace.md,
          BrandSpace.md,
          BrandSpace.md,
          0,
        ),
        child: BrandCard(
          padding: const EdgeInsets.all(BrandSpace.md),
          child: Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 20,
                color: BrandColors.textMuted,
              ),
              const SizedBox(width: BrandSpace.sm),
              Expanded(
                child: Text(
                  'Weather en route is a Ranmap Pro feature.',
                  style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
                ),
              ),
              BrandSecondaryButton(
                label: 'Unlock',
                expand: false,
                onPressed: () =>
                    showPaywall(context, feature: PremiumFeature.weather),
              ),
            ],
          ),
        ),
      );
    }

    final weather =
        ref.watch(tripStopWeatherProvider(tripId)).valueOrNull ?? const {};
    if (weather.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (final stop in stops) {
      final w = weather[stop.id];
      if (w == null || !w.hasData) continue;
      final v = weatherVisual(w.weatherCode);
      final rain = w.precipitationProbability;
      rows.add(
        BrandListRow(
          icon: v.icon,
          iconColor: BrandColors.primary,
          title: stop.name,
          subtitle: v.label,
          showChevron: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.temperatureC != null)
                Text(
                  '${w.temperatureC!.round()}°C',
                  style: BrandText.weight(
                    BrandText.labelSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
              if (rain != null && rain >= 20) ...[
                const SizedBox(width: BrandSpace.sm),
                BrandPill(
                  label: '$rain%',
                  icon: Icons.water_drop_rounded,
                  iconColor: BrandColors.primary,
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BrandSpace.md,
        BrandSpace.md,
        BrandSpace.md,
        0,
      ),
      child: BrandCard(
        padding: const EdgeInsets.symmetric(
          horizontal: BrandSpace.md,
          vertical: BrandSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: BrandSpace.sm),
              child: BrandSectionHeader(
                icon: Icons.cloud_outlined,
                title: 'Weather en route',
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDeleteDialog(BuildContext context, String title) =>
    showAppConfirmDialog(
      context,
      title: title,
      confirmLabel: 'Delete',
      destructive: true,
    );

Widget _dismissBackground() {
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: BrandSpace.lg),
    decoration: BoxDecoration(
      color: BrandColors.error,
      borderRadius: BrandRadii.cardRadius,
    ),
    child: const Icon(Icons.delete_outline, color: Colors.white),
  );
}

/// A brand colour per expense category, so the ledger's breakdown bars read
/// apart without needing a legend.
Color _ledgerCategoryColor(String category) => switch (category) {
  'fuel' => BrandColors.primary,
  'food' => BrandColors.accentPeach,
  'toll' => BrandColors.accentMint,
  'lodging' => BrandColors.primaryContainer,
  _ => BrandColors.textMuted,
};
