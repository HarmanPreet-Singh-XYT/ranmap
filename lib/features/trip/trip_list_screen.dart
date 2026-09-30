import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/services/supabase_service.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_skeleton.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import '../notifications/notifications_bell.dart';
import 'new_trip_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_providers.dart';

class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  /// The selected status filter; `null` means "All".
  TripStatus? _filter;

  Future<void> _newTrip() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewTripScreen()));
    ref.invalidate(myTripsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(myTripsProvider);
    final invitesAsync = ref.watch(tripInvitesProvider);

    return BrandScaffold(
      bottomSafeArea: false,
      header: const BrandHeader(
        title: 'Trips',
        showBack: false,
        action: NotificationsBell(),
      ),
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTripsProvider);
              ref.invalidate(tripInvitesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(top: BrandSpace.md, bottom: 96),
              children: [
                invitesAsync.when(
                  data: (invites) {
                    if (invites.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandSectionHeader(
                          icon: Icons.mark_email_unread_rounded,
                          title: 'Invites',
                          trailing: BrandPill(
                            label: '${invites.length}',
                            bold: true,
                          ),
                        ),
                        const SizedBox(height: BrandSpace.sm),
                        for (final invite in invites) ...[
                          _InviteCard(invite: invite),
                          const SizedBox(height: BrandSpace.sm),
                        ],
                        const SizedBox(height: BrandSpace.md),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => const Padding(
                    padding: EdgeInsets.only(bottom: BrandSpace.md),
                    child: BrandAlert(message: "Couldn't load invites."),
                  ),
                ),
                tripsAsync.when(
                  data: (trips) {
                    if (trips.isEmpty) {
                      return _TripsEmptyState(onPlan: _newTrip);
                    }
                    // The filter appears once there's more than one trip and
                    // then stays put, so it no longer flickers in and out as
                    // the status mix changes under the user.
                    final showFilter = trips.length > 1;
                    // Ignore a stale selection if the filter is hidden.
                    final activeFilter = showFilter ? _filter : null;
                    final visible = activeFilter == null
                        ? trips
                        : trips.where((t) => t.status == activeFilter).toList();
                    return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrandSectionHeader(
                              icon: Icons.route_rounded,
                              title: 'Your trips',
                              trailing: BrandPill(label: '${trips.length}'),
                            ),
                            if (showFilter) ...[
                              const SizedBox(height: BrandSpace.sm),
                              _TripStatusFilter(
                                trips: trips,
                                selected: activeFilter,
                                onSelect: (status) =>
                                    setState(() => _filter = status),
                              ),
                            ],
                            const SizedBox(height: BrandSpace.sm),
                            if (visible.isEmpty && activeFilter != null)
                              BrandEmptyState(
                                icon: _statusIcon(activeFilter),
                                title: 'Nothing here yet',
                                message:
                                    'No ${_statusFilterLabel(activeFilter)} trips.',
                                action: BrandSecondaryButton(
                                  label: 'Show all',
                                  expand: false,
                                  onPressed: () =>
                                      setState(() => _filter = null),
                                ),
                              )
                            else ...[
                              for (final trip in visible) ...[
                                _TripCard(trip: trip),
                                const SizedBox(height: BrandSpace.sm),
                              ],
                            ],
                          ],
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(
                          begin: 0.04,
                          end: 0,
                          curve: Curves.easeOutCubic,
                        );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: BrandSpace.md),
                    child: BrandSkeletonList(count: 4),
                  ),
                  error: (e, _) => ErrorRetry(
                    error: e,
                    onRetry: () => ref.invalidate(myTripsProvider),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: BrandSpace.md,
            bottom: BrandSpace.md,
            child: BrandFab(
              icon: Icons.add_rounded,
              tooltip: 'New trip',
              onPressed: _newTrip,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Trips-tab empty state: the bundled Big Sur shot as a rounded hero above
/// the standard [BrandEmptyState] copy, so a blank list still feels like a place.
class _TripsEmptyState extends StatelessWidget {
  const _TripsEmptyState({required this.onPlan});

  final VoidCallback onPlan;

  static const String _art = 'assets/images/scenic/big_sur.jpg';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BrandRadii.cardRadius,
          child: Image.asset(
            _art,
            fit: BoxFit.cover,
            height: 140,
            width: double.infinity,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: BrandSpace.md),
        BrandEmptyState(
          icon: Icons.alt_route_rounded,
          title: 'No trips yet',
          message: 'Start one to invite your crew and hit the road together.',
          action: BrandPrimaryButton(
            label: 'Plan a trip',
            trailingIcon: Icons.add_rounded,
            expand: false,
            onPressed: onPlan,
          ),
        ),
      ],
    );
  }
}

/// The `All · Active · Planned · Completed` segmented status filter. Counts are
/// read off the real trip list; a zero count is simply left off the pill.
class _TripStatusFilter extends StatelessWidget {
  const _TripStatusFilter({
    required this.trips,
    required this.selected,
    required this.onSelect,
  });

  final List<Trip> trips;
  final TripStatus? selected;
  final ValueChanged<TripStatus?> onSelect;

  static const List<TripStatus?> _options = <TripStatus?>[
    null,
    TripStatus.active,
    TripStatus.planned,
    TripStatus.completed,
  ];

  String _label(TripStatus? status) {
    if (status == null) return 'All';
    final name = _statusFilterLabel(status);
    final count = trips.where((t) => t.status == status).length;
    return count > 0 ? '$name $count' : name;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BrandSpace.sm,
      runSpacing: BrandSpace.sm,
      children: [
        for (final status in _options)
          _FilterPill(
            label: _label(status),
            selected: selected == status,
            onTap: () => onSelect(status),
          ),
      ],
    );
  }
}

/// A tappable brand pill. Selected uses the green container + on-primary text;
/// unselected sits on the neutral low container with body text.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BrandSpace.xs),
        child: BrandPill(
          label: label,
          bold: true,
          background: selected
              ? BrandColors.primaryContainer
              : BrandColors.surfaceContainerLow,
          foreground: selected ? BrandColors.onPrimary : BrandColors.textBody,
        ),
      ),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.invite});

  final Map<String, dynamic> invite;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(tripRepositoryProvider).respondToInvite(
            tripId: widget.invite['trip_id'] as String,
            accept: accept,
          );
      ref.invalidate(tripInvitesProvider);
      ref.invalidate(myTripsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final trip = invite['trips'] as Map<String, dynamic>?;
    final creator = trip?['creator'] as Map<String, dynamic>?;

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_rounded, size: 18, color: BrandColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip?['title'] as String? ?? 'Trip',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.weight(
                    BrandText.titleSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Invited by @${creator?['username'] ?? 'someone'}',
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.md),
          Row(
            children: [
              Expanded(
                child: BrandPrimaryButton(
                  label: 'Accept',
                  trailingIcon: null,
                  glow: false,
                  loading: _busy,
                  onPressed: _busy ? null : () => _respond(true),
                ),
              ),
              const SizedBox(width: BrandSpace.gutterSm),
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Decline',
                  onPressed: _busy ? null : () => _respond(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripCard extends ConsumerStatefulWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  @override
  ConsumerState<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends ConsumerState<_TripCard> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(tripRepositoryProvider).startTrip(widget.trip.id);
      ref.invalidate(myTripsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TripDetailScreen(trip: widget.trip)),
  );

  /// Deletes (creator) or leaves (member) the trip, after confirming.
  Future<void> _removeOrLeave(bool isCreator) async {
    final trip = widget.trip;
    final confirmed = await showAppConfirmDialog(
      context,
      title: isCreator ? 'Delete trip?' : 'Leave trip?',
      message: isCreator
          ? 'This permanently deletes the trip, its stops and expenses for everyone.'
          : 'You will stop sharing your location on this trip.',
      confirmLabel: isCreator ? 'Delete' : 'Leave',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final repo = ref.read(tripRepositoryProvider);
      if (isCreator) {
        await repo.deleteTrip(trip.id);
      } else {
        await repo.leaveTrip(trip.id);
      }
      refreshTripData(ref, tripId: trip.id);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  void _showActions() {
    final trip = widget.trip;
    final isCreator = trip.createdBy == SupabaseService.currentUser?.id;
    showAppActionSheet(
      context,
      title: trip.title,
      subtitle: _statusLabel(trip.status),
      actions: [
        AppSheetAction(
          label: 'Open',
          icon: Icons.open_in_new_rounded,
          onSelected: _open,
        ),
        if (trip.status == TripStatus.planned)
          AppSheetAction(
            label: 'Start now',
            icon: Icons.play_arrow_rounded,
            onSelected: _start,
          ),
        if (isCreator)
          AppSheetAction(
            label: 'Delete trip',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () => _removeOrLeave(true),
          )
        else if (trip.status != TripStatus.completed)
          AppSheetAction(
            label: 'Leave trip',
            icon: Icons.logout_rounded,
            destructive: true,
            onSelected: () => _removeOrLeave(false),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return GestureDetector(
      onLongPress: _showActions,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip))),
      behavior: HitTestBehavior.opaque,
      child: BrandCard(
        padding: const EdgeInsets.all(BrandSpace.md),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: _tint(trip.status),
                borderRadius: BrandRadii.miniRadius,
              ),
              child: Icon(
                _statusIcon(trip.status),
                size: 22,
                color: BrandColors.primary,
              ),
            ),
            const SizedBox(width: BrandSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.weight(
                      BrandText.titleSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  const SizedBox(height: 6),
                  BrandPill(
                    label: _statusLabel(trip.status),
                    background: _pillBackground(trip.status),
                    foreground: _pillForeground(trip.status),
                    bold: true,
                  ),
                  if (trip.status == TripStatus.planned &&
                      trip.scheduledStart != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 14,
                          color: BrandColors.textMuted,
                        ),
                        const SizedBox(width: BrandSpace.xs),
                        Flexible(
                          child: Text(
                            DateFormat.yMMMd().add_jm().format(
                              trip.scheduledStart!.toLocal(),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrandText.bodySm.copyWith(
                              color: BrandColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: BrandSpace.sm),
            if (trip.status == TripStatus.planned)
              BrandPrimaryButton(
                label: 'Start',
                trailingIcon: null,
                glow: false,
                expand: false,
                loading: _busy,
                onPressed: _busy ? null : _start,
              )
            else
              Icon(
                trip.status == TripStatus.active
                    ? Icons.navigation_rounded
                    : Icons.chevron_right_rounded,
                color: trip.status == TripStatus.active
                    ? BrandColors.primaryContainer
                    : BrandColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

  static Color _tint(TripStatus status) => switch (status) {
    TripStatus.active => BrandColors.accentMint.withValues(alpha: 0.4),
    TripStatus.planned => BrandColors.accentSky.withValues(alpha: 0.35),
    TripStatus.completed => BrandColors.secondaryFixed.withValues(alpha: 0.5),
    TripStatus.cancelled => BrandColors.surfaceContainerHigh,
  };

  static Color _pillBackground(TripStatus status) => switch (status) {
    TripStatus.active => BrandColors.primaryContainer,
    TripStatus.planned => BrandColors.surfaceContainerHigh,
    TripStatus.completed => BrandColors.secondaryFixed,
    TripStatus.cancelled => BrandColors.surfaceContainer,
  };

  static Color _pillForeground(TripStatus status) => switch (status) {
    TripStatus.active => BrandColors.onPrimary,
    TripStatus.planned => BrandColors.textBody,
    TripStatus.completed => BrandColors.onSecondaryFixed,
    TripStatus.cancelled => BrandColors.textMuted,
  };

  static String _statusLabel(TripStatus status) => switch (status) {
    TripStatus.planned => 'Planned',
    TripStatus.active => 'Active now',
    TripStatus.completed => 'Completed',
    TripStatus.cancelled => 'Cancelled',
  };
}

/// Glyph for a trip status, shared by the card pod and the filter's empty state.
IconData _statusIcon(TripStatus status) => switch (status) {
  TripStatus.active => Icons.navigation_rounded,
  TripStatus.planned => Icons.map_rounded,
  TripStatus.completed => Icons.flag_rounded,
  TripStatus.cancelled => Icons.cancel_rounded,
};

/// Short, filter-facing label for a trip status (`Active`, not `Active now`).
String _statusFilterLabel(TripStatus status) => switch (status) {
  TripStatus.planned => 'Planned',
  TripStatus.active => 'Active',
  TripStatus.completed => 'Completed',
  TripStatus.cancelled => 'Cancelled',
};
