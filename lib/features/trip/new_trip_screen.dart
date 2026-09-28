import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../core/constants/avatars.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/group.dart';
import '../../data/models/route_template.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../social/social_providers.dart';
import 'plan_route_screen.dart';
import 'trip_providers.dart';

/// The currencies offered when creating a trip. Stored as an ISO 4217 code on
/// the trip and used to label its ledger and fuel figures.
const _kTripCurrencies = <({String code, String label})>[
  (code: 'USD', label: 'USD — US dollar'),
  (code: 'EUR', label: 'EUR — Euro'),
  (code: 'GBP', label: 'GBP — British pound'),
  (code: 'INR', label: 'INR — Indian rupee'),
  (code: 'CAD', label: 'CAD — Canadian dollar'),
  (code: 'AUD', label: 'AUD — Australian dollar'),
];

/// "Start a trip" flow: give it a title, optionally plan a route (origin +
/// destination + a chosen alternate route from the Directions API), invite
/// group members by username, then create it. Starting the trip (going
/// active) happens from the map screen once at least the creator is ready
/// to roll.
class NewTripScreen extends ConsumerStatefulWidget {
  const NewTripScreen({super.key});

  @override
  ConsumerState<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends ConsumerState<NewTripScreen> {
  final _titleCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final List<String> _invitees = [];

  /// `username -> avatar_id` for invitees added from the friends list, so the
  /// roster can render their real avatar. A username typed by hand has no
  /// profile row here, so its avatar falls back to [kDefaultAvatarSeed].
  final Map<String, String> _inviteeAvatarIds = {};
  PlannedRoute? _plannedRoute;

  /// Optional planned start time; null (the default) means the trip starts as
  /// soon as the creator goes active. Sent through as `scheduled_start` on
  /// create — see [Trip.scheduledStart].
  DateTime? _scheduledStart;

  /// ISO 4217 code the trip's expenses and ledger will use.
  String _currency = 'USD';

  /// The group this trip is being planned for, if any. Sent through as
  /// `group_id` on create so the trip is associated with (and visible to) the
  /// crew.
  String? _groupId;

  /// Bumped when the schedule is cleared so the date/time fields rebuild empty.
  /// Their managed controls hold their own state, so a plain `initial: null`
  /// change wouldn't reset them.
  int _scheduleEpoch = 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  Future<void> _planRoute() async {
    final result = await Navigator.of(context).push<PlannedRoute>(
      MaterialPageRoute(builder: (_) => const PlanRouteScreen()),
    );
    if (result != null) setState(() => _plannedRoute = result);
  }

  /// Populates the route from one of the user's saved route templates.
  Future<void> _pickTemplate() async {
    final List<RouteTemplate> templates;
    try {
      templates = await ref.read(routeTemplatesProvider.future);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final usable = templates.where((t) => t.isUsable).toList();
    if (usable.isEmpty) {
      if (mounted) {
        showAppToast(
          context,
          'No saved routes yet — save one from a trip\'s menu.',
        );
      }
      return;
    }
    if (!mounted) return;
    final selected = await showFSheet<RouteTemplate>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              for (final (i, t) in usable.indexed) ...[
                if (i > 0) const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.alt_route_rounded,
                  iconColor: BrandColors.primary,
                  title: t.name,
                  subtitle: [
                    t.originName,
                    t.destinationName,
                  ].whereType<String>().join(' → '),
                  showChevron: false,
                  onTap: () => Navigator.of(context).pop(t),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    setState(
      () => _plannedRoute = PlannedRoute(
        originName: selected.originName ?? 'Start',
        originPoint: selected.originPoint!,
        destinationName: selected.destinationName ?? 'Finish',
        destinationPoint: selected.destinationPoint!,
        routePolyline: selected.routePolyline!,
      ),
    );
  }

  void _addInvitee() {
    final username = _inviteCtrl.text.trim();
    if (username.isEmpty || _invitees.contains(username)) return;
    setState(() {
      _invitees.add(username);
      _inviteCtrl.clear();
    });
  }

  Future<void> _pickFromFriends() async {
    final friendRows = await ref.read(friendsProvider.future);
    final myUid = SupabaseService.currentUser?.id;
    final friends = friendRows
        .map((row) {
          final isRequester = row['requester_id'] == myUid;
          return (isRequester ? row['addressee'] : row['requester'])
              as Map<String, dynamic>?;
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    if (!mounted) return;

    if (friends.isEmpty) {
      showAppToast(
        context,
        'No friends yet — add some from Profile > Friends.',
      );
      return;
    }

    final selected = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: ListView(
          shrinkWrap: true,
          children: [
            BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final profile in friends)
                    _CrewRow(
                      seed:
                          profile['avatar_id'] as String? ?? kDefaultAvatarSeed,
                      username: profile['username'] as String,
                      onTap: _invitees.contains(profile['username'] as String)
                          ? null
                          : () =>
                                Navigator.of(context)
                                    .pop(profile['username'] as String),
                      trailing:
                          _invitees.contains(profile['username'] as String)
                          ? const BrandPill(
                              label: 'Invited',
                              icon: Icons.check_rounded,
                              bold: true,
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
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

    if (selected != null && !_invitees.contains(selected)) {
      // Remember the picked friend's real avatar_id so the roster shows their
      // face rather than a generic glyph.
      final picked = friends.firstWhere(
        (profile) => profile['username'] == selected,
        orElse: () => const <String, dynamic>{},
      );
      setState(() {
        _invitees.add(selected);
        final avatarId = picked['avatar_id'] as String?;
        if (avatarId != null && avatarId.isNotEmpty) {
          _inviteeAvatarIds[selected] = avatarId;
        }
      });
    }
  }

  void _setScheduleDate(DateTime? date) {
    setState(() {
      if (date == null) {
        _scheduledStart = null;
        return;
      }
      // Keep whatever time was already chosen (or now) when only the date moves.
      final time = _scheduledStart ?? DateTime.now();
      _scheduledStart = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _setScheduleTime(FTime? time) {
    if (time == null) return;
    setState(() {
      final day = _scheduledStart ?? DateTime.now();
      _scheduledStart = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _clearSchedule() {
    setState(() {
      _scheduledStart = null;
      _scheduleEpoch++;
    });
  }

  /// Choose the group this trip belongs to (or none). Uses an empty-string
  /// sentinel for "none" so the choice sheet has a concrete value.
  Future<void> _pickGroup(List<Group> groups) async {
    final choice = await showAppChoiceSheet<String>(
      context,
      title: 'Group',
      selected: _groupId ?? '',
      options: [
        (value: '', label: 'No group — standalone trip'),
        for (final g in groups) (value: g.id, label: g.name),
      ],
    );
    if (choice == null) return;
    setState(() => _groupId = choice.isEmpty ? null : choice);
  }

  Future<void> _createTrip() async {
    final title = _titleCtrl.text.trim();
    final titleValidationError = nameError(title, label: 'Trip name');
    if (titleValidationError != null) {
      setState(() => _error = titleValidationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(tripRepositoryProvider);
    try {
      final uid = SupabaseService.currentUserId;
      final route = _plannedRoute;
      final trip = await repo.createTrip(
        Trip.draft(
          createdBy: uid,
          title: title,
          groupId: _groupId,
          currency: _currency,
          scheduledStart: _scheduledStart,
          originName: route?.originName,
          originPoint: route?.originPoint,
          destinationName: route?.destinationName,
          destinationPoint: route?.destinationPoint,
          routePolyline: route?.routePolyline,
        ),
      );

      final failedInvites = <String>[];
      for (final username in _invitees) {
        try {
          final invited = await repo.inviteByUsername(
            tripId: trip.id,
            username: username,
          );
          if (!invited) failedInvites.add(username);
        } catch (_) {
          failedInvites.add(username);
        }
      }

      ref.invalidate(myTripsProvider);

      if (!mounted) return;
      if (failedInvites.isNotEmpty) {
        // Don't drop this in a toast that vanishes with the screen: name the
        // handles that failed and point at the trip's Crew tab, where they can
        // be retried once the spelling is right.
        await _showInviteFailures(failedInvites);
      }
      if (!mounted) return;
      Navigator.of(context).pop(trip);
    } catch (e) {
      if (!mounted) return;
      // Over the free active-trip cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.trips);
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The trip was created, but some handles couldn't be found. Names them and
  /// explains where to retry, rather than a toast that disappears with the
  /// screen.
  Future<void> _showInviteFailures(List<String> failed) {
    final handles = failed.map((u) => '@$u').join(', ');
    return showFSheet<void>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.person_off_rounded, color: BrandColors.primary),
                const SizedBox(width: BrandSpace.gutterSm),
                Expanded(
                  child: Text(
                    'Some invites didn\'t send',
                    style: BrandText.titleMd.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BrandSpace.md),
            Text(
              'Your trip is ready, but we couldn\'t find $handles. Check the '
              'spelling, then invite them again from the trip\'s Crew tab.',
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
            const SizedBox(height: BrandSpace.lg),
            BrandPrimaryButton(
              label: 'Got it',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
    String? selectedGroupName;
    for (final g in groups) {
      if (g.id == _groupId) {
        selectedGroupName = g.name;
        break;
      }
    }
    return BrandScaffold(
      header: BrandHeader(
        title: 'New trip',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          const _FieldLabel('Trip name'),
          BrandTextField(
            controller: _titleCtrl,
            hint: 'Weekend to the coast',
            maxLength: kNameMaxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandCard(
            padding: const EdgeInsets.all(BrandSpace.md),
            child: Row(
              children: [
                Icon(Icons.alt_route_rounded, color: BrandColors.primary),
                const SizedBox(width: BrandSpace.gutterSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _plannedRoute == null
                            ? 'No route planned'
                            : 'Route planned',
                        style: BrandText.weight(
                          BrandText.titleSm,
                          700,
                        ).copyWith(color: BrandColors.textHeadline),
                      ),
                      if (_plannedRoute == null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Optional — pick an origin, destination, and route',
                          style: BrandText.bodySm.copyWith(
                            color: BrandColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _pickTemplate,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: BrandColors.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bookmark_outline_rounded,
                      size: 20,
                      color: BrandColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
                BrandSecondaryButton(
                  label: _plannedRoute == null ? 'Plan route' : 'Change',
                  expand: false,
                  onPressed: _planRoute,
                ),
              ],
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandSectionHeader(
            icon: Icons.schedule_rounded,
            title: 'Scheduled start',
            subtitle: 'Optional — leave blank to start when you go active',
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: _scheduledStart == null
                  ? Icons.bolt_rounded
                  : Icons.event_available_rounded,
              iconColor: BrandColors.primary,
              title: _scheduledStart == null
                  ? 'Immediately'
                  : DateFormat.yMMMd().add_jm().format(_scheduledStart!),
              subtitle: _scheduledStart == null
                  ? 'No start time planned'
                  : 'Planned start time the crew can see',
              showChevron: false,
              trailing: _scheduledStart == null
                  ? null
                  : BrandSecondaryButton(
                      label: 'Clear',
                      expand: false,
                      onPressed: _clearSchedule,
                    ),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          // Keyed on the epoch so "Clear" rebuilds the fields empty: their
          // managed controls hold their own value, so passing `initial: null`
          // on its own wouldn't reset them.
          KeyedSubtree(
            key: ValueKey('schedule-date-$_scheduleEpoch'),
            child: FDateField.calendar(
              label: const Text('Date'),
              selectionControl: FDateSelectionControl.managedSingle(
                initial: _scheduledStart,
                onChange: _setScheduleDate,
              ),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          KeyedSubtree(
            key: ValueKey('schedule-time-$_scheduleEpoch'),
            child: FTimeField.picker(
              label: const Text('Time'),
              control: FTimeFieldControl.managed(
                initial: _scheduledStart == null
                    ? null
                    : FTime(_scheduledStart!.hour, _scheduledStart!.minute),
                onChange: _setScheduleTime,
              ),
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.payments_rounded,
            title: 'Currency',
            subtitle: "Used for this trip's expenses and ledger",
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: Icons.payments_rounded,
              iconColor: BrandColors.primary,
              title: 'Trip currency',
              subtitle: _kTripCurrencies
                  .firstWhere((c) => c.code == _currency)
                  .label,
              onTap: () async {
                final choice = await showAppChoiceSheet<String>(
                  context,
                  title: 'Trip currency',
                  selected: _currency,
                  options: [
                    for (final c in _kTripCurrencies)
                      (value: c.code, label: c.label),
                  ],
                );
                if (choice != null) setState(() => _currency = choice);
              },
              trailing: BrandPill(label: _currency),
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.groups_rounded,
            title: 'Group',
            subtitle: 'Optional — plan this trip with a crew',
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: BrandListRow(
              icon: Icons.groups_rounded,
              iconColor: BrandColors.primary,
              title: 'Group',
              subtitle: _groupId == null
                  ? (groups.isEmpty
                        ? 'No groups yet — create one from Groups'
                        : 'Standalone trip')
                  : (selectedGroupName ?? 'Group selected'),
              onTap: groups.isEmpty ? null : () => _pickGroup(groups),
              trailing: BrandPill(label: _groupId == null ? 'None' : 'Set'),
            ),
          ),
          const SizedBox(height: BrandSpace.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invite group members',
                  style: BrandText.weight(
                    BrandText.titleSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
              ),
              BrandSecondaryButton(
                label: 'From friends',
                leading: Icon(
                  Icons.group_add_rounded,
                  size: 18,
                  color: BrandColors.textHeadlineAlt,
                ),
                expand: false,
                onPressed: _pickFromFriends,
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          const _FieldLabel('Username'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: BrandTextField(
                  controller: _inviteCtrl,
                  hint: 'theirname',
                  onSubmitted: (_) => _addInvitee(),
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              BrandPrimaryButton(
                label: 'Add',
                trailingIcon: null,
                glow: false,
                expand: false,
                onPressed: _addInvitee,
              ),
            ],
          ),
          if (_invitees.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.gutterSm),
            BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final username in _invitees)
                    _CrewRow(
                      seed: _inviteeAvatarIds[username] ?? kDefaultAvatarSeed,
                      username: username,
                      onTap: () => setState(() {
                        _invitees.remove(username);
                        _inviteeAvatarIds.remove(username);
                      }),
                      trailing: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: BrandColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Create trip',
            onPressed: _saving ? null : _createTrip,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

/// A small muted field caption sitting above a [BrandTextField].
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: BrandText.labelMd.copyWith(color: BrandColors.textBody),
    ),
  );
}

/// A crew roster row: a member's real [AvatarView], their handle, and an
/// optional trailing action.
///
/// Mirrors [BrandListRow]'s geometry, but that row's icon slot takes an
/// [IconData], so this row hosts the [AvatarView] directly instead.
class _CrewRow extends StatelessWidget {
  const _CrewRow({
    required this.seed,
    required this.username,
    this.trailing,
    this.onTap,
  });

  /// The member's `avatar_id`, or [kDefaultAvatarSeed] when it isn't known
  /// (e.g. a username typed by hand rather than picked from friends).
  final String seed;
  final String username;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AvatarView(
            seed: seed,
            size: 40,
            background: BrandColors.surfaceContainerLow,
            accentColor: BrandColors.primary,
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
          if (trailing != null) ...[
            const SizedBox(width: BrandSpace.sm),
            trailing!,
          ],
        ],
      ),
    ),
  );
}
