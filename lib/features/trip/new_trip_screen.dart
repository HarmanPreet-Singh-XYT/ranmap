import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../social/social_providers.dart';
import 'plan_route_screen.dart';
import 'trip_providers.dart';

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
  PlannedRoute? _plannedRoute;
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
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(BrandSpace.md),
        children: [
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: Column(
              children: [
                for (final profile in friends)
                  BrandListRow(
                    icon: Icons.person,
                    iconBackground: BrandColors.surfaceContainerLow,
                    iconColor: BrandColors.primary,
                    title: '@${profile['username']}',
                    showChevron: !_invitees.contains(
                      profile['username'] as String,
                    ),
                    onTap: _invitees.contains(profile['username'] as String)
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pop(profile['username'] as String),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (selected != null && !_invitees.contains(selected)) {
      setState(() => _invitees.add(selected));
    }
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
          await repo.inviteByUsername(tripId: trip.id, username: username);
        } catch (_) {
          failedInvites.add(username);
        }
      }

      ref.invalidate(myTripsProvider);

      if (!mounted) return;
      if (failedInvites.isNotEmpty) {
        showAppToast(
          context,
          'Trip created. Could not find: ${failedInvites.join(', ')}',
        );
      }
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

  @override
  Widget build(BuildContext context) {
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
                BrandSecondaryButton(
                  label: _plannedRoute == null ? 'Plan route' : 'Change',
                  expand: false,
                  onPressed: _planRoute,
                ),
              ],
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
            Wrap(
              spacing: BrandSpace.sm,
              runSpacing: BrandSpace.sm,
              children: _invitees
                  .map(
                    (u) => GestureDetector(
                      onTap: () => setState(() => _invitees.remove(u)),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BrandSpace.gutterSm,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.surfaceContainerLow,
                          borderRadius: BrandRadii.pill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$u',
                              style: BrandText.labelMd.copyWith(
                                color: BrandColors.textHeadline,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: BrandColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
