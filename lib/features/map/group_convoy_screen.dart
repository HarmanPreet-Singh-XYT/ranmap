import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
// `Position` is geolocator's (latitude/longitude); the map engine's own
// `Position` (GeoJSON) is hidden so `Geo.pos` can still be used for the
// navigate-to-member hand-off.
import 'package:geolocator/geolocator.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/geo_distance.dart';
import '../../core/util/units.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group_alert.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/services/supabase_service.dart';
import '../social/group_photos_screen.dart';
import '../social/social_providers.dart';
import 'live_sync_providers.dart';
import 'map_engine/map_engine.dart' hide Position;
import 'navigate_to_member_sheet.dart';

/// A crew member's live state in the convoy roster.
enum _CrewState { sharing, stopped, behind, idle }

/// The group as a live convoy: who's sharing, how far away they are, whether
/// anyone has stopped or fallen behind, plus the safety/coordination layer —
/// SOS, "regroup here" rendezvous points, and arrival check-ins.
///
/// This is the group-scoped counterpart to the trip's live map: presence and
/// alerts belong to the crew, not to a single run.
class GroupConvoyScreen extends ConsumerStatefulWidget {
  const GroupConvoyScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  ConsumerState<GroupConvoyScreen> createState() => _GroupConvoyScreenState();
}

class _GroupConvoyScreenState extends ConsumerState<GroupConvoyScreen> {
  /// Whether this device has checked itself in to a given rendezvous alert, so
  /// a proximity crossing fires the RPC once (not on every GPS fix).
  final Map<String, bool> _checkedIn = {};

  /// A crew member more than this far from you is flagged "behind"; stopped
  /// below [_stoppedSpeedMps].
  static const double _behindMeters = 2000;
  static const double _stoppedSpeedMps = 0.7;

  /// Proximity radius for auto check-in at a rendezvous (arrive inside
  /// [_arriveMeters], release past [_departMeters] to avoid flapping).
  static const double _arriveMeters = 150;
  static const double _departMeters = 300;

  Future<void> _toggleSharing(bool on) async {
    final notifier = ref.read(convoyGroupIdProvider.notifier);
    if (on) {
      await notifier.enable(widget.groupId);
    } else {
      await notifier.disable();
    }
  }

  Future<void> _sos() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Send an SOS?',
      message:
          'Your crew will be alerted and can see your live location. Use this '
          'if you need help.',
      confirmLabel: 'Send SOS',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final pos = ref.read(devicePositionProvider).valueOrNull;
    try {
      await ref
          .read(convoyRepositoryProvider)
          .sendAlert(
            groupId: widget.groupId,
            kind: GroupAlertKind.sos,
            lat: pos?.latitude,
            lng: pos?.longitude,
          );
      if (mounted) showAppToast(context, 'SOS sent to your crew.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _regroup() async {
    final pos = ref.read(devicePositionProvider).valueOrNull;
    if (pos == null) {
      showAppToast(context, 'Waiting for your location…', error: true);
      return;
    }
    try {
      await ref
          .read(convoyRepositoryProvider)
          .sendAlert(
            groupId: widget.groupId,
            kind: GroupAlertKind.regroup,
            message: 'Regroup at my location',
            lat: pos.latitude,
            lng: pos.longitude,
          );
      if (mounted) showAppToast(context, 'Rendezvous point shared.');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _resolve(GroupAlert alert) async {
    try {
      await ref.read(convoyRepositoryProvider).resolveAlert(alert.id);
      ref.invalidate(groupAlertsProvider(widget.groupId));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Auto check-in/out at the nearest open rendezvous point.
  void _maybeCheckIn(Position? pos) {
    if (pos == null) return;
    final alerts =
        ref.read(groupAlertsProvider(widget.groupId)).valueOrNull ?? const [];
    for (final alert in alerts) {
      if (alert.kind != GroupAlertKind.regroup ||
          alert.isResolved ||
          !alert.hasPoint) {
        continue;
      }
      final meters = haversineMeters(
        pos.latitude,
        pos.longitude,
        alert.lat!,
        alert.lng!,
      );
      final present = _checkedIn[alert.id] ?? false;
      if (!present && meters < _arriveMeters) {
        _checkedIn[alert.id] = true;
        unawaited(
          ref
              .read(convoyRepositoryProvider)
              .checkIn(alertId: alert.id, arrived: true),
        );
      } else if (present && meters > _departMeters) {
        _checkedIn[alert.id] = false;
        unawaited(
          ref
              .read(convoyRepositoryProvider)
              .checkIn(alertId: alert.id, arrived: false),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate check-ins whenever our position moves.
    ref.listen(devicePositionProvider, (_, next) {
      _maybeCheckIn(next.valueOrNull);
    });

    final group =
        ref.watch(groupProvider(widget.groupId)).valueOrNull?.name ??
        widget.groupName;
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final sharing = ref.watch(convoyGroupIdProvider) == widget.groupId;
    final ownPos = ref.watch(devicePositionProvider).valueOrNull;
    final myUid = SupabaseService.currentUser?.id;

    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final liveAsync = ref.watch(groupLiveSyncProvider(widget.groupId));
    final alertsAsync = ref.watch(groupAlertsProvider(widget.groupId));

    final members = membersAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    final activeMembers = [
      for (final m in members)
        if (m['status'] == 'active') m,
    ];
    final live = liveAsync.valueOrNull ?? const <String, MemberLocation>{};

    return BrandScaffold(
      header: BrandHeader(
        title: 'Convoy · $group',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          _sharingCard(sharing, live.length),
          const SizedBox(height: BrandSpace.lg),
          BrandSectionHeader(
            icon: Icons.share_location_rounded,
            title: 'Live crew',
            trailing: BrandPill(
              label: '${live.length}/${activeMembers.length} live',
              bold: true,
            ),
          ),
          const SizedBox(height: BrandSpace.sm),
          membersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(BrandSpace.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () =>
                  ref.invalidate(groupMembersProvider(widget.groupId)),
            ),
            data: (_) {
              if (activeMembers.isEmpty) {
                return const BrandEmptyState(
                  imageAsset: 'assets/images/scenic/convoy_pack_scenic.jpg',
                  icon: Icons.groups_outlined,
                  title: 'Assemble your convoy crew',
                  message:
                      'Invite members to this group to track live road positions and telemetry on the map.',
                );
              }
              final rows = [
                for (final m in activeMembers)
                  _rosterRow(m, live, ownPos, myUid, unit),
              ];
              return BrandCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: BrandSpace.md,
                  vertical: BrandSpace.xs,
                ),
                child: Column(children: rows),
              );
            },
          ),
          const SizedBox(height: BrandSpace.lg),
          _actions(ownPos != null),
          const SizedBox(height: BrandSpace.lg),
          BrandSectionHeader(icon: Icons.campaign_rounded, title: 'Alerts'),
          const SizedBox(height: BrandSpace.sm),
          alertsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (alerts) {
              final active = alerts.where((a) => !a.isResolved).toList();
              if (active.isEmpty) {
                return BrandCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BrandSpace.md,
                    vertical: BrandSpace.xs,
                  ),
                  child: BrandListRow(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: BrandColors.primary,
                    title: 'All clear',
                    subtitle: 'No active alerts in this convoy',
                    showChevron: false,
                  ),
                );
              }
              return Column(
                children: [
                  for (final alert in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BrandSpace.sm),
                      child: _AlertCard(
                        alert: alert,
                        activeCount: activeMembers.length,
                        onResolve: () => _resolve(alert),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: Icons.photo_library_outlined,
              title: 'Crew photos',
              subtitle: 'Photos shared with this group',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupPhotosScreen(
                    groupId: widget.groupId,
                    groupName: group,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rosterRow(
    Map<String, dynamic> member,
    Map<String, MemberLocation> live,
    Position? ownPos,
    String? myUid,
    DistanceUnit unit,
  ) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final userId = member['user_id'] as String;
    final username = profile?['username'] as String? ?? 'member';
    final seed = profile?['avatar_id'] as String? ?? 'default';
    final loc = live[userId];
    final isMe = userId == myUid;

    double? meters;
    double? bearing;
    if (loc != null && ownPos != null) {
      meters = haversineMeters(
        ownPos.latitude,
        ownPos.longitude,
        loc.lat,
        loc.lng,
      );
      bearing = _bearing(ownPos.latitude, ownPos.longitude, loc.lat, loc.lng);
    }

    _CrewState state = _CrewState.idle;
    if (loc != null) {
      final stopped = loc.speedMps != null && loc.speedMps! < _stoppedSpeedMps;
      if (stopped) {
        state = _CrewState.stopped;
      } else if (meters != null && meters > _behindMeters) {
        state = _CrewState.behind;
      } else {
        state = _CrewState.sharing;
      }
    }

    return GestureDetector(
      onTap: loc == null || isMe
          ? null
          : () => showNavigateToMemberSheet(
              context,
              destination: Geo.pos(loc.lat, loc.lng),
              username: username,
              vehicleType: profile?['vehicle_type'] as String?,
            ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            AvatarView(
              seed: seed,
              size: 40,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? '@$username (you)' : '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.titleSm.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  Text(
                    meters != null
                        ? formatShortDistance(meters, unit)
                        : 'Not sharing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (bearing != null)
              Transform.rotate(
                angle: bearing,
                child: Icon(
                  Icons.navigation_rounded,
                  size: 16,
                  color: BrandColors.textMuted,
                ),
              ),
            const SizedBox(width: 8),
            _statePill(state),
          ],
        ),
      ),
    );
  }

  Widget _statePill(_CrewState state) => switch (state) {
    _CrewState.sharing => const BrandPill(
      label: 'Live',
      icon: Icons.bolt_rounded,
      bold: true,
    ),
    _CrewState.stopped => const BrandPill(
      label: 'Stopped',
      icon: Icons.pause_circle_outline_rounded,
    ),
    _CrewState.behind => BrandPill(
      label: 'Behind',
      icon: Icons.trending_down_rounded,
      background: BrandColors.errorContainer,
      foreground: BrandColors.error,
      iconColor: BrandColors.error,
    ),
    _CrewState.idle => const BrandPill(label: 'Idle'),
  };

  Widget _sharingCard(bool sharing, int liveCount) {
    return BrandCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: BrandSpace.xs,
      ),
      child: BrandListRow(
        icon: sharing
            ? Icons.share_location_rounded
            : Icons.location_disabled_rounded,
        iconColor: BrandColors.primary,
        title: 'Share my location',
        subtitle: sharing
            ? 'Your crew can see you live'
            : 'Turn on to ride together in real time',
        showChevron: false,
        onTap: null,
        trailing: FSwitch(value: sharing, onChange: _toggleSharing),
      ),
    );
  }

  Widget _actions(bool hasPosition) {
    return Row(
      children: [
        Expanded(
          child: BrandPressable(
            onTap: hasPosition ? _sos : null,
            enabled: hasPosition,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: BrandColors.errorContainer,
                borderRadius: BrandRadii.pill,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sos_rounded,
                    size: 20,
                    color: BrandColors.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SOS',
                    style: BrandText.weight(
                      BrandText.labelLg,
                      700,
                    ).copyWith(color: BrandColors.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: BrandSpace.md),
        Expanded(
          child: BrandSecondaryButton(
            label: 'Regroup here',
            leading: Icon(
              Icons.pin_drop_rounded,
              size: 18,
              color: BrandColors.textHeadlineAlt,
            ),
            onPressed: hasPosition ? _regroup : null,
          ),
        ),
      ],
    );
  }
}

/// One active convoy alert: SOS or a rendezvous point with arrival progress.
class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.activeCount,
    required this.onResolve,
  });

  final GroupAlert alert;
  final int activeCount;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final isSos = alert.kind == GroupAlertKind.sos;
    final accent = isSos ? BrandColors.error : BrandColors.primary;
    final name = alert.creatorUsername != null
        ? '@${alert.creatorUsername}'
        : 'A member';

    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: isSos
                      ? BrandColors.errorContainer
                      : BrandColors.secondaryFixed.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSos ? Icons.sos_rounded : Icons.pin_drop_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSos ? 'SOS from $name' : 'Rendezvous · $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.titleSm.copyWith(
                        color: BrandColors.textHeadline,
                      ),
                    ),
                    Text(
                      alert.message?.isNotEmpty == true
                          ? alert.message!
                          : isSos
                          ? 'Needs help — see their live location'
                          : '${alert.presentCount}/$activeCount arrived',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: BrandSecondaryButton(
              label: 'Mark resolved',
              expand: false,
              onPressed: onResolve,
            ),
          ),
        ],
      ),
    );
  }
}

/// Initial great-circle bearing (radians) so the roster arrow points at them.
double _bearing(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
  return math.atan2(y, x);
}
