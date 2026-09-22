import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/trip.dart';
import '../../data/services/supabase_service.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No friends yet — add some from Profile > Friends.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: friends.map((profile) {
            final username = profile['username'] as String;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@$username'),
              enabled: !_invitees.contains(username),
              onTap: () => Navigator.of(context).pop(username),
            );
          }).toList(),
        ),
      ),
    );

    if (selected != null && !_invitees.contains(selected)) {
      setState(() => _invitees.add(selected));
    }
  }

  Future<void> _createTrip() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your trip a name');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trip created. Could not find: ${failedInvites.join(', ')}')),
        );
      }
      Navigator.of(context).pop(trip);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _titleCtrl,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(labelText: 'Trip name'),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alt_route_rounded),
              title: Text(_plannedRoute == null ? 'No route planned' : 'Route planned'),
              subtitle: _plannedRoute == null
                  ? const Text('Optional — pick an origin, destination, and route')
                  : null,
              trailing: TextButton(
                onPressed: _planRoute,
                child: Text(_plannedRoute == null ? 'Plan route' : 'Change'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Invite group members', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _pickFromFriends,
                  icon: const Icon(Icons.group_add),
                  label: const Text('From friends'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inviteCtrl,
                    decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
                    onSubmitted: (_) => _addInvitee(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _addInvitee, icon: const Icon(Icons.add)),
              ],
            ),
            if (_invitees.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _invitees
                    .map((u) => Chip(
                          label: Text('@$u'),
                          onDeleted: () => setState(() => _invitees.remove(u)),
                        ))
                    .toList(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _createTrip,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create trip'),
            ),
          ],
        ),
      ),
    );
  }
}
