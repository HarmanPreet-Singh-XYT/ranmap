import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/offline/outbox_providers.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/services/supabase_service.dart';
import '../map/map_engine/map_engine.dart';
import '../profile/edit_profile_screen.dart';
import 'change_credential_screen.dart';
import 'settings_providers.dart';

/// App settings: preferences, account, privacy, data and about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final profile = ref.watch(myProfileProvider).valueOrNull;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Settings'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SectionLabel('Preferences', color: c),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(Icons.brightness_6_rounded),
                title: const Text('Theme'),
                details: Text(_themeLabel(settings.themeMode)),
                onPress: () async {
                  final choice = await showAppChoiceSheet<ThemeMode>(
                    context,
                    title: 'Theme',
                    selected: settings.themeMode,
                    options: const [
                      (value: ThemeMode.system, label: 'System'),
                      (value: ThemeMode.light, label: 'Light'),
                      (value: ThemeMode.dark, label: 'Dark'),
                    ],
                  );
                  if (choice != null) notifier.setThemeMode(choice);
                },
              ),
              FTile(
                prefix: const Icon(Icons.straighten_rounded),
                title: const Text('Distance units'),
                details: Text(settings.distanceUnit == DistanceUnit.miles ? 'Miles' : 'Kilometers'),
                onPress: () async {
                  final choice = await showAppChoiceSheet<DistanceUnit>(
                    context,
                    title: 'Distance units',
                    selected: settings.distanceUnit,
                    options: const [
                      (value: DistanceUnit.kilometers, label: 'Kilometers'),
                      (value: DistanceUnit.miles, label: 'Miles'),
                    ],
                  );
                  if (choice != null) notifier.setDistanceUnit(choice);
                },
              ),
              FTile(
                prefix: const Icon(Icons.layers_rounded),
                title: const Text('Map style'),
                details: Text(RanmapMapStyle.fromId(settings.mapStyleId).label),
                onPress: () async {
                  final choice = await showAppChoiceSheet<String>(
                    context,
                    title: 'Map style',
                    selected: settings.mapStyleId,
                    options: [
                      for (final style in RanmapMapStyle.values)
                        (value: style.name, label: style.label),
                    ],
                  );
                  if (choice != null) notifier.setMapStyleId(choice);
                },
              ),
              FTile(
                prefix: const Icon(Icons.apartment_rounded),
                title: const Text('3D buildings'),
                suffix: FSwitch(value: settings.mapThreeD, onChange: notifier.setMapThreeD),
                onPress: () => notifier.setMapThreeD(!settings.mapThreeD),
              ),
              FTile(
                prefix: const Icon(Icons.landscape_rounded),
                title: const Text('Terrain'),
                suffix: FSwitch(value: settings.mapTerrain, onChange: notifier.setMapTerrain),
                onPress: () => notifier.setMapTerrain(!settings.mapTerrain),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('Notifications', color: c),
          const _NotificationsSection(),
          const SizedBox(height: 22),
          _SectionLabel('Account', color: c),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(Icons.person_rounded),
                title: const Text('Edit profile'),
                suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                enabled: profile != null,
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile!)),
                ),
              ),
              FTile(
                prefix: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change password'),
                suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangeCredentialScreen(kind: CredentialKind.password),
                  ),
                ),
              ),
              FTile(
                prefix: const Icon(Icons.mail_outline_rounded),
                title: const Text('Change email'),
                suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangeCredentialScreen(kind: CredentialKind.email),
                  ),
                ),
              ),
              FTile(
                prefix: const Icon(Icons.devices_rounded),
                title: const Text('Sign out other devices'),
                subtitle: const Text('Keep this device signed in'),
                onPress: () async {
                  final confirmed = await showAppConfirmDialog(
                    context,
                    title: 'Sign out other devices?',
                    message: 'Every other signed-in device will need to sign in again.',
                    confirmLabel: 'Sign out',
                  );
                  if (!confirmed) return;
                  try {
                    await SupabaseService.auth.signOut(scope: SignOutScope.others);
                    if (context.mounted) showAppToast(context, 'Signed out of other devices.');
                  } catch (e) {
                    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                  }
                },
              ),
              FTile(
                variant: .destructive,
                prefix: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete account'),
                subtitle: const Text('Permanently deletes your account and data'),
                onPress: () async {
                  // Two confirmations: this is irreversible.
                  final first = await showAppConfirmDialog(
                    context,
                    title: 'Delete your account?',
                    message:
                        'This permanently deletes your profile, trips, photos, chats and messages. It cannot be undone.',
                    confirmLabel: 'Continue',
                    destructive: true,
                  );
                  if (!first || !context.mounted) return;
                  final second = await showAppConfirmDialog(
                    context,
                    title: 'Are you absolutely sure?',
                    message: 'There is no way to recover your data after this.',
                    confirmLabel: 'Delete account',
                    destructive: true,
                  );
                  if (!second || !context.mounted) return;
                  try {
                    await ref.read(accountRepositoryProvider).deleteAccount();
                    // The account is gone; end the local session so the router
                    // sends the user back to the auth screens.
                    await SupabaseService.auth.signOut();
                  } catch (e) {
                    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionLabel('Privacy', color: c),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(Icons.photo_library_outlined),
                title: const Text('Default photo visibility'),
                subtitle: const Text('For new photos pinned to the map'),
                details: Text(_visibilityLabel(settings.photoVisibility)),
                onPress: () async {
                  final choice = await showAppChoiceSheet<String>(
                    context,
                    title: 'Default photo visibility',
                    selected: settings.photoVisibility,
                    options: const [
                      (value: 'private', label: 'Only me'),
                      (value: 'group', label: 'Trip members'),
                      (value: 'public', label: 'Public'),
                    ],
                  );
                  if (choice != null) notifier.setPhotoVisibility(choice);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          FAlert(
            icon: const Icon(Icons.location_on_outlined),
            title: const Text('Location sharing'),
            subtitle: const Text(
              'While a trip is active, your position is shared with that trip’s members so they can see you on the map. It stops when the trip ends or you leave it.',
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel('Data', color: c),
          Builder(
            builder: (context) {
              final outbox = ref.watch(outboxProvider);
              return FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Clear offline queue'),
                    subtitle: const Text('Discard writes waiting to sync'),
                    details: ValueListenableBuilder<int>(
                      valueListenable: outbox.pending,
                      builder: (context, count, _) => Text('$count'),
                    ),
                    onPress: () async {
                      final confirmed = await showAppConfirmDialog(
                        context,
                        title: 'Clear offline queue?',
                        message: 'Any changes still waiting to sync will be permanently discarded.',
                        confirmLabel: 'Clear',
                        destructive: true,
                      );
                      if (!confirmed) return;
                      await outbox.clear();
                      if (context.mounted) showAppToast(context, 'Offline queue cleared.');
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          _SectionLabel('About', color: c),
          FTileGroup(
            children: [
              FTile(
                prefix: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                details: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return Text(info == null ? '—' : '${info.version} (${info.buildNumber})');
                  },
                ),
              ),
              FTile(
                prefix: const Icon(Icons.description_outlined),
                title: const Text('Open-source licenses'),
                suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                onPress: () => showLicensePage(context: context, applicationName: 'Ranmap'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  static String _visibilityLabel(String visibility) => switch (visibility) {
        'private' => 'Only me',
        'public' => 'Public',
        _ => 'Trip members',
      };
}

class _NotificationsSection extends ConsumerStatefulWidget {
  const _NotificationsSection();

  @override
  ConsumerState<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<_NotificationsSection> {
  /// The value the user last chose, held so toggles feel instant and don't
  /// snap back while the save round-trips.
  NotificationPreferences? _local;

  Future<void> _update(NotificationPreferences next) async {
    setState(() => _local = next);
    try {
      await ref.read(notificationRepositoryProvider).save(next);
    } catch (e) {
      if (!mounted) return;
      // Fall back to the server's view so the UI doesn't claim a save that
      // didn't happen.
      setState(() => _local = null);
      showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return ref.watch(notificationPreferencesProvider).when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: FCircularProgress(size: .sm)),
          ),
          error: (e, _) => const FAlert(
            variant: .destructive,
            title: Text("Couldn't load notification settings."),
          ),
          data: (server) {
            final prefs = _local ?? server;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FTileGroup(
                  children: [
                    FTile(
                      prefix: const Icon(Icons.mail_outline_rounded),
                      title: const Text('Trip invites'),
                      subtitle: const Text('When someone invites you to a trip'),
                      suffix: FSwitch(
                        value: prefs.tripInvites,
                        onChange: (v) => _update(prefs.copyWith(tripInvites: v)),
                      ),
                      onPress: () => _update(prefs.copyWith(tripInvites: !prefs.tripInvites)),
                    ),
                    FTile(
                      prefix: const Icon(Icons.forum_outlined),
                      title: const Text('Chat messages'),
                      subtitle: const Text('New messages in your trip and group channels'),
                      suffix: FSwitch(
                        value: prefs.chatMessages,
                        onChange: (v) => _update(prefs.copyWith(chatMessages: v)),
                      ),
                      onPress: () => _update(prefs.copyWith(chatMessages: !prefs.chatMessages)),
                    ),
                    FTile(
                      prefix: const Icon(Icons.route_outlined),
                      title: const Text('Trip updates'),
                      subtitle: const Text('When a scheduled trip starts'),
                      suffix: FSwitch(
                        value: prefs.tripUpdates,
                        onChange: (v) => _update(prefs.copyWith(tripUpdates: v)),
                      ),
                      onPress: () => _update(prefs.copyWith(tripUpdates: !prefs.tripUpdates)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Push delivery turns on once this build registers a device token with the server.',
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            );
          },
        );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.color});

  final String text;
  final NavColors color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: color.activeRoute,
          ),
        ),
      );
}
