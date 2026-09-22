import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/services/supabase_service.dart';
import '../social/friends_screen.dart';
import '../social/groups_screen.dart';
import '../social/social_providers.dart';
import 'edit_profile_screen.dart';
import 'linked_socials_screen.dart';
import 'trip_history_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.auth.signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text('No profile found.'));
          final initial = profile.username.isEmpty
              ? '?'
              : profile.username.substring(0, 1).toUpperCase();
          final vehicleLabel = kVehicleOptions
              .firstWhere((v) => v.id == profile.vehicleType,
                  orElse: () => VehicleOption(profile.vehicleType, profile.vehicleType))
              .label;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.primaryContainer,
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('@${profile.username}', style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 4),
              Center(child: Text('Vehicle: $vehicleLabel')),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit profile'),
                ),
              ),
              const SizedBox(height: 24),
              Builder(builder: (context) {
                final incomingCount = ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;
                return ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: const Text('Friends'),
                  trailing: incomingCount > 0
                      ? Badge(label: Text('$incomingCount'), child: const Icon(Icons.chevron_right))
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  ),
                );
              }),
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const Text('Groups'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GroupsScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('Linked socials'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LinkedSocialsScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('Trip stats & history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.danger),
                title: const Text('Sign out', style: TextStyle(color: AppTheme.danger)),
                onTap: () => _signOut(context),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myProfileProvider)),
      ),
    );
  }
}
