import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/offline/outbox_providers.dart';
import '../../core/providers/emergency_contact_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/push/push_service.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/services/supabase_service.dart';
import '../map/map_engine/map_engine.dart';
import '../premium/manage_subscription.dart';
import '../premium/premium_providers.dart';
import '../profile/edit_profile_screen.dart';
import 'change_credential_screen.dart';
import 'settings_providers.dart';

/// App settings: preferences, notifications, account, privacy, data and about —
/// in the brand's card + icon-row language.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final isPro = ref.watch(isProProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Settings',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          const BrandSectionHeader(
            icon: Icons.tune_rounded,
            title: 'Preferences',
          ),
          const SizedBox(height: BrandSpace.sm),
          _Card(
            children: [
              BrandListRow(
                icon: Icons.brightness_6_rounded,
                title: 'Theme',
                onTap: () async {
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
                trailing: BrandPill(label: _themeLabel(settings.themeMode)),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.straighten_rounded,
                title: 'Distance units',
                onTap: () async {
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
                trailing: BrandPill(
                  label: settings.distanceUnit == DistanceUnit.miles
                      ? 'Miles'
                      : 'Kilometers',
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.layers_rounded,
                title: 'Map style',
                onTap: () async {
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
                trailing: BrandPill(
                  label: RanmapMapStyle.fromId(settings.mapStyleId).label,
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.apartment_rounded,
                title: '3D buildings',
                // Only the switch toggles: a row onTap plus the switch's own
                // onChange could both fire for one tap and cancel out.
                onTap: null,
                trailing: FSwitch(
                  value: settings.mapThreeD,
                  onChange: notifier.setMapThreeD,
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.landscape_rounded,
                title: 'Terrain',
                onTap: null,
                trailing: FSwitch(
                  value: settings.mapTerrain,
                  onChange: notifier.setMapTerrain,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
          ),
          const SizedBox(height: BrandSpace.sm),
          const _NotificationsSection(),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.person_rounded,
            title: 'Account',
          ),
          const SizedBox(height: BrandSpace.sm),
          _Card(
            children: [
              BrandListRow(
                icon: Icons.person_outline_rounded,
                title: 'Edit profile',
                onTap: profile == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(profile: profile),
                        ),
                      ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.lock_outline_rounded,
                title: 'Change password',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangeCredentialScreen(
                      kind: CredentialKind.password,
                    ),
                  ),
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.mail_outline_rounded,
                title: 'Change email',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangeCredentialScreen(
                      kind: CredentialKind.email,
                    ),
                  ),
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.devices_rounded,
                title: 'Sign out other devices',
                subtitle: 'Keep this device signed in',
                onTap: () async {
                  final confirmed = await showAppConfirmDialog(
                    context,
                    title: 'Sign out other devices?',
                    message: 'Every other signed-in device will need to sign in again.',
                    confirmLabel: 'Sign out',
                  );
                  if (!confirmed) return;
                  try {
                    await SupabaseService.auth.signOut(
                      scope: SignOutScope.others,
                    );
                    if (context.mounted) {
                      showAppToast(context, 'Signed out of other devices.');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showAppToast(context, friendlyError(e), error: true);
                    }
                  }
                },
              ),
              if (isPro) ...[
                const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.stars_rounded,
                  title: 'Manage subscription',
                  subtitle: 'Change or cancel your Ranmap Pro plan',
                  onTap: () => openManageSubscription(context),
                ),
              ],
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.delete_forever_outlined,
                title: 'Delete account',
                subtitle: 'Permanently deletes your account and data',
                titleColor: BrandColors.error,
                iconColor: BrandColors.error,
                onTap: () async {
                  // Two confirmations: this is irreversible.
                  final first = await showAppConfirmDialog(
                    context,
                    title: 'Delete your account?',
                    message: 'This permanently deletes your profile, trips, photos, chats and messages. It cannot be undone.',
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
                    if (context.mounted) {
                      showAppToast(context, friendlyError(e), error: true);
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy',
          ),
          const SizedBox(height: BrandSpace.sm),
          _Card(
            children: [
              BrandListRow(
                icon: Icons.photo_library_outlined,
                title: 'Default photo visibility',
                subtitle: 'For new photos pinned to the map',
                onTap: () async {
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
                trailing: BrandPill(
                  label: _visibilityLabel(settings.photoVisibility),
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: settings.shareLocation
                    ? Icons.share_location_rounded
                    : Icons.location_disabled_rounded,
                title: 'Share live location',
                subtitle: 'Broadcast your position to the active trip',
                // Only the switch toggles, matching the 3D/terrain rows.
                onTap: null,
                trailing: FSwitch(
                  value: settings.shareLocation,
                  onChange: notifier.setShareLocation,
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.headset_mic_rounded,
                title: 'Auto-join trip voice',
                subtitle: 'Join the convoy voice channel when a trip starts',
                onTap: null,
                trailing: FSwitch(
                  value: settings.voiceAutoJoin,
                  onChange: notifier.setVoiceAutoJoin,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          const _LocationSharingNote(),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.health_and_safety_outlined,
            title: 'Safety',
          ),
          const SizedBox(height: BrandSpace.sm),
          _Card(
            children: [
              Builder(
                builder: (context) {
                  final contact = ref.watch(emergencyContactProvider);
                  return BrandListRow(
                    icon: Icons.emergency_share_outlined,
                    iconColor: BrandColors.primary,
                    title: 'Emergency contact',
                    subtitle: contact.isSet
                        ? '${contact.label} · ${contact.phone}'
                        : 'Text someone your location when you send an SOS',
                    onTap: () => _editEmergencyContact(context, ref),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.cloud_done_rounded,
            title: 'Data',
          ),
          const SizedBox(height: BrandSpace.sm),
          Builder(
            builder: (context) {
              final outbox = ref.watch(outboxProvider);
              return _Card(
                children: [
                  BrandListRow(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Clear offline queue',
                    subtitle: 'Discard writes waiting to sync',
                    onTap: () async {
                      final confirmed = await showAppConfirmDialog(
                        context,
                        title: 'Clear offline queue?',
                        message: 'Any changes still waiting to sync will be permanently discarded.',
                        confirmLabel: 'Clear',
                        destructive: true,
                      );
                      if (!confirmed) return;
                      await outbox.clear();
                      if (context.mounted) {
                        showAppToast(context, 'Offline queue cleared.');
                      }
                    },
                    trailing: ValueListenableBuilder<int>(
                      valueListenable: outbox.pending,
                      builder: (context, count, _) =>
                          BrandPill(label: '$count'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.info_outline_rounded,
            title: 'About',
          ),
          const SizedBox(height: BrandSpace.sm),
          _Card(
            children: [
              BrandListRow(
                icon: Icons.description_outlined,
                title: 'Open-source licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Ranmap',
                ),
              ),
              const BrandRowDivider(),
              BrandListRow(
                icon: Icons.tag_rounded,
                title: 'Version',
                showChevron: false,
                trailing: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return BrandPill(
                      label: info == null
                          ? '—'
                          : '${info.version} (${info.buildNumber})',
                    );
                  },
                ),
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

  /// Edits the locally-stored emergency contact (never uploaded).
  Future<void> _editEmergencyContact(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(emergencyContactProvider);
    final result = await showFDialog<(String?, String?)>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => BrandSheetSurface.dialog(
          child: _EmergencyContactContent(
            initialName: current.name,
            initialPhone: current.phone,
          ),
        ),
      ),
    );
    if (result == null) return;
    await ref
        .read(emergencyContactProvider.notifier)
        .save(name: result.$1, phone: result.$2);
    if (context.mounted) showAppToast(context, 'Emergency contact saved.');
  }
}

/// A white card holding a stack of rows.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BrandCard(
    padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md, vertical: 4),
    child: Column(children: children),
  );
}

class _LocationSharingNote extends StatelessWidget {
  const _LocationSharingNote();

  @override
  Widget build(BuildContext context) {
    return const BrandAlert(
      variant: BrandAlertVariant.info,
      message: 'While a trip is active, your position is shared with that trip’s members so they can see you on the map. It stops when the trip ends, you leave it, or you turn off Share live location.',
    );
  }
}

class _NotificationsSection extends ConsumerStatefulWidget {
  const _NotificationsSection();

  @override
  ConsumerState<_NotificationsSection> createState() =>
      _NotificationsSectionState();
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

  /// Requests the OS notification permission (a user gesture) and registers
  /// this device on success, then refreshes the status row.
  Future<void> _enablePush() async {
    final granted = await requestPushPermission();
    ref.invalidate(pushStatusProvider);
    if (!mounted) return;
    showAppToast(
      context,
      granted
          ? 'Notifications turned on for this device.'
          : 'Notifications are off — you can enable them in system settings.',
      error: !granted,
    );
  }

  /// The device-level push affordance, above the per-category preferences: it
  /// reflects the OS permission (and reports honestly when the build has no
  /// push configuration), so the toggles below aren't the only signal.
  Widget _deviceStatusCard() {
    return ref
        .watch(pushStatusProvider)
        .maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (status) => _Card(
            children: [
              switch (status) {
                PushStatus.unsupported => const BrandListRow(
                  icon: Icons.notifications_off_outlined,
                  title: 'Push unavailable',
                  subtitle: 'This build has no push configuration.',
                  showChevron: false,
                ),
                PushStatus.denied => BrandListRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Turn on notifications',
                  subtitle:
                      'Allow Ranmap to notify you about invites and messages',
                  onTap: _enablePush,
                ),
                PushStatus.authorized => const BrandListRow(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications on',
                  subtitle: 'This device can receive push notifications',
                  showChevron: false,
                ),
              },
            ],
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _deviceStatusCard(),
        const SizedBox(height: 10),
        ref
            .watch(notificationPreferencesProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: FCircularProgress(size: .sm)),
              ),
              error: (e, _) => const BrandAlert(
                message: "Couldn't load notification settings.",
              ),
              data: (server) {
                final prefs = _local ?? server;
                return _Card(
                  children: [
                    BrandListRow(
                      icon: Icons.mail_outline_rounded,
                      title: 'Trip invites',
                      subtitle: 'When someone invites you to a trip',
                      trailing: FSwitch(
                        value: prefs.tripInvites,
                        onChange: (v) =>
                            _update(prefs.copyWith(tripInvites: v)),
                      ),
                    ),
                    const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.forum_outlined,
                      title: 'Chat messages',
                      subtitle: 'New messages in your trip and group channels',
                      trailing: FSwitch(
                        value: prefs.chatMessages,
                        onChange: (v) =>
                            _update(prefs.copyWith(chatMessages: v)),
                      ),
                    ),
                    const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.groups_rounded,
                      title: 'Group invites',
                      subtitle:
                          'When you are added to a group or approved to join',
                      trailing: FSwitch(
                        value: prefs.groupInvites,
                        onChange: (v) =>
                            _update(prefs.copyWith(groupInvites: v)),
                      ),
                    ),
                    const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.sos_rounded,
                      title: 'Convoy alerts',
                      subtitle: 'SOS and regroup signals from your crew',
                      trailing: FSwitch(
                        value: prefs.convoyAlerts,
                        onChange: (v) =>
                            _update(prefs.copyWith(convoyAlerts: v)),
                      ),
                    ),
                    const BrandRowDivider(),
                    BrandListRow(
                      icon: Icons.route_outlined,
                      title: 'Trip updates',
                      subtitle: 'When a scheduled trip starts',
                      trailing: FSwitch(
                        value: prefs.tripUpdates,
                        onChange: (v) =>
                            _update(prefs.copyWith(tripUpdates: v)),
                      ),
                    ),
                  ],
                );
              },
            ),
      ],
    );
  }
}

/// Collects a name + phone for the emergency contact. Returns
/// `(name, phone)`; both may be empty (clearing it).
class _EmergencyContactContent extends StatefulWidget {
  const _EmergencyContactContent({this.initialName, this.initialPhone});

  final String? initialName;
  final String? initialPhone;

  @override
  State<_EmergencyContactContent> createState() =>
      _EmergencyContactContentState();
}

class _EmergencyContactContentState extends State<_EmergencyContactContent> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _phoneCtrl = TextEditingController(
    text: widget.initialPhone,
  );
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final phone = _phoneCtrl.text.trim();
    if (phone.isNotEmpty) {
      final validationError = phoneError(phone);
      if (validationError != null) {
        setState(() => _error = validationError);
        return;
      }
    }
    Navigator.of(context).pop((_nameCtrl.text.trim(), phone));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Emergency contact',
            style: BrandText.titleMd.copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: BrandSpace.md),
          BrandTextField(
            controller: _nameCtrl,
            hint: 'Name (optional)',
            leadingIcon: Icons.person_outline_rounded,
            maxLength: 60,
          ),
          const SizedBox(height: BrandSpace.md),
          BrandTextField(
            controller: _phoneCtrl,
            hint: '+15551234567',
            leadingIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.sm),
            Text(
              _error!,
              style: BrandText.bodySm.copyWith(color: BrandColors.error),
            ),
          ],
          const SizedBox(height: BrandSpace.sm),
          Text(
            'Stored on this device only. Used when you send an SOS with no data.',
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.lg),
          Row(
            children: [
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              Expanded(
                child: BrandPrimaryButton(
                  label: 'Save',
                  glow: false,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
