import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/services/supabase_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import '../settings/settings_screen.dart';
import '../social/friends_screen.dart';
import '../social/groups_screen.dart';
import '../social/social_providers.dart';
import 'edit_profile_screen.dart';
import 'linked_socials_screen.dart';
import 'trip_history_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You can sign back in any time.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    try {
      await SupabaseService.auth.signOut();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final profileAsync = ref.watch(myProfileProvider);
    final incomingCount = ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;
    final isPro = ref.watch(isProProvider);

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: const Text('Profile'),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.settings_rounded),
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(child: Text('No profile found.', style: TextStyle(color: c.mutedForeground)));
          }
          final vehicleLabel = kVehicleOptions
              .firstWhere((v) => v.id == profile.vehicleType,
                  orElse: () => VehicleOption(profile.vehicleType, profile.vehicleType))
              .label;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: AvatarView(seed: profile.avatarId, size: 88)),
              const SizedBox(height: 14),
              if (profile.displayName != null && profile.displayName!.trim().isNotEmpty) ...[
                Center(
                  child: Text(
                    profile.displayName!,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.foreground),
                  ),
                ),
                const SizedBox(height: 2),
                Center(child: Text('@${profile.username}', style: TextStyle(color: c.mutedForeground))),
              ] else
                Center(
                  child: Text(
                    '@${profile.username}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.foreground),
                  ),
                ),
              const SizedBox(height: 4),
              Center(child: Text('Vehicle: $vehicleLabel', style: TextStyle(color: c.mutedForeground))),
              const SizedBox(height: 14),
              Center(
                child: FButton(
                  variant: .outline,
                  size: .sm,
                  onPress: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
                  ),
                  prefix: const Icon(Icons.edit_rounded),
                  child: const Text('Edit profile'),
                ),
              ),
              const SizedBox(height: 24),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(Icons.person_rounded),
                    title: const Text('Friends'),
                    suffix: incomingCount > 0
                        ? FBadge(child: Text('$incomingCount'))
                        : Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FriendsScreen()),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(Icons.groups_rounded),
                    title: const Text('Groups'),
                    suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GroupsScreen()),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(Icons.link_rounded),
                    title: const Text('Linked socials'),
                    suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LinkedSocialsScreen()),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(Icons.bar_chart_rounded),
                    title: const Text('Trip stats & history'),
                    suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FTileGroup(
                children: [
                  FTile(
                    prefix: Icon(
                      Icons.workspace_premium_rounded,
                      color: isPro ? c.success : c.highway,
                    ),
                    title: const Text('Ranmap Pro'),
                    subtitle: Text(
                      isPro ? 'Active — thanks for the support' : 'Unlock AI, voice & unlimited search',
                    ),
                    suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                    onPress: () => showPaywall(context, feature: PremiumFeature.aiAssistant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FTileGroup(
                children: [
                  FTile(
                    variant: .destructive,
                    prefix: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onPress: () => _signOut(context),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myProfileProvider)),
      ),
    );
  }
}
