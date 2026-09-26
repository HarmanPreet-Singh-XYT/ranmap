import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/trip.dart';
import 'new_trip_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_providers.dart';

class TripListScreen extends ConsumerWidget {
  const TripListScreen({super.key});

  Future<void> _newTrip(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewTripScreen()));
    ref.invalidate(myTripsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(myTripsProvider);
    final invitesAsync = ref.watch(tripInvitesProvider);

    return BrandScaffold(
      bottomSafeArea: false,
      header: const BrandHeader(title: 'Trips', showBack: false),
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
                      return BrandEmptyState(
                        icon: Icons.alt_route_rounded,
                        title: 'No trips yet',
                        message: 'Start one to invite your crew and hit the road together.',
                        action: BrandPrimaryButton(
                          label: 'Plan a trip',
                          trailingIcon: Icons.add_rounded,
                          expand: false,
                          onPressed: () => _newTrip(context, ref),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandSectionHeader(
                          icon: Icons.route_rounded,
                          title: 'Your trips',
                          trailing: BrandPill(label: '${trips.length}'),
                        ),
                        const SizedBox(height: BrandSpace.sm),
                        for (final trip in trips) ...[
                          _TripCard(trip: trip),
                          const SizedBox(height: BrandSpace.sm),
                        ],
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: BrandSpace.xl),
                    child: Center(child: CircularProgressIndicator()),
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
            child: BrandPrimaryButton(
              label: 'New trip',
              leadingIcon: Icons.add_rounded,
              trailingIcon: null,
              expand: false,
              onPressed: () => _newTrip(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.invite});

  final Map<String, dynamic> invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = invite['trips'] as Map<String, dynamic>?;
    final creator = trip?['creator'] as Map<String, dynamic>?;
    final tripId = invite['trip_id'] as String;

    Future<void> respond(bool accept) async {
      try {
        await ref
            .read(tripRepositoryProvider)
            .respondToInvite(tripId: tripId, accept: accept);
        ref.invalidate(tripInvitesProvider);
        ref.invalidate(myTripsProvider);
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, friendlyError(e), error: true);
        }
      }
    }

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mail_rounded,
                size: 18,
                color: BrandColors.primary,
              ),
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
                  onPressed: () => respond(true),
                ),
              ),
              const SizedBox(width: BrandSpace.gutterSm),
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Decline',
                  onPressed: () => respond(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripCard extends ConsumerWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(tripRepositoryProvider).startTrip(trip.id);
      ref.invalidate(myTripsProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
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
                _icon(trip.status),
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
                onPressed: () => _start(context, ref),
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

  static IconData _icon(TripStatus status) => switch (status) {
    TripStatus.active => Icons.navigation_rounded,
    TripStatus.planned => Icons.map_rounded,
    TripStatus.completed => Icons.flag_rounded,
    TripStatus.cancelled => Icons.cancel_rounded,
  };

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
