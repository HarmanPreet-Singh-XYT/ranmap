import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
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
    final friends = friendRows.map((row) {
      final isRequester = row['requester_id'] == myUid;
      return (isRequester ? row['addressee'] : row['requester']) as Map<String, dynamic>?;
    }).whereType<Map<String, dynamic>>().toList();

    if (!mounted) return;

    if (friends.isEmpty) {
      showAppToast(context, 'No friends yet — add some from Profile > Friends.');
      return;
    }

    final selected = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          FTileGroup(
            children: [
              for (final profile in friends)
                FTile(
                  enabled: !_invitees.contains(profile['username'] as String),
                  prefix: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: NavColors.of(context).surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person, color: NavColors.of(context).activeRoute, size: 20),
                  ),
                  title: Text('@${profile['username']}'),
                  onPress: () => Navigator.of(context).pop(profile['username'] as String),
                ),
            ],
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
      final trip = await repo.createTrip(Trip.draft(
        createdBy: uid,
        title: title,
        originName: route?.originName,
        originPoint: route?.originPoint,
        destinationName: route?.destinationName,
        destinationPoint: route?.destinationPoint,
        routePolyline: route?.routePolyline,
      ));

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
        showAppToast(context, 'Trip created. Could not find: ${failedInvites.join(', ')}');
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
    final c = NavColors.of(context);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('New trip'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FTextField(
            control: FTextFieldControl.managed(
              controller: _titleCtrl,
              onChange: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            label: const Text('Trip name'),
            hint: 'Weekend to the coast',
            maxLength: kNameMaxLength,
          ),
          const SizedBox(height: 20),
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: c.activeRoute),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _plannedRoute == null ? 'No route planned' : 'Route planned',
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.foreground),
                        ),
                        if (_plannedRoute == null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Optional — pick an origin, destination, and route',
                            style: TextStyle(color: c.mutedForeground, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  FButton(
                    variant: .outline,
                    size: .sm,
                    onPress: _planRoute,
                    child: Text(_plannedRoute == null ? 'Plan route' : 'Change'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invite group members',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground),
                ),
              ),
              FButton(
                variant: .ghost,
                size: .sm,
                onPress: _pickFromFriends,
                prefix: const Icon(Icons.group_add),
                child: const Text('From friends'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FTextField(
                  control: FTextFieldControl.managed(controller: _inviteCtrl),
                  label: const Text('Username'),
                  hint: 'theirname',
                  onSubmit: (_) => _addInvitee(),
                ),
              ),
              const SizedBox(width: 8),
              FButton.icon(
                onPress: _addInvitee,
                child: const Icon(Icons.add),
              ),
            ],
          ),
          if (_invitees.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _invitees
                  .map((u) => FButton(
                        variant: .outline,
                        size: .xs,
                        semanticsLabel: 'Remove @$u',
                        onPress: () => setState(() => _invitees.remove(u)),
                        suffix: const Icon(Icons.close),
                        child: Text('@$u'),
                      ))
                  .toList(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            FAlert(variant: .destructive, title: Text(_error!)),
          ],
          const SizedBox(height: 28),
          FButton(
            size: .lg,
            onPress: _saving ? null : _createTrip,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: AppSpinner(color: Colors.white),
                  )
                : const Text('Create trip'),
          ),
        ],
      ),
    );
  }
}
