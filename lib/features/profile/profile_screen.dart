import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/vehicle_display.dart';
import '../../core/offline/outbox_providers.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/push/push_service.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/units.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/profile.dart';
import '../../data/services/supabase_service.dart';
import '../premium/premium_providers.dart';
import '../settings/settings_screen.dart';
import '../social/friends_screen.dart';
import '../social/groups_screen.dart';
import '../social/social_providers.dart';
import '../trip/trip_providers.dart';
import 'linked_socials_screen.dart';
import 'profile_providers.dart';
import 'trip_history_screen.dart';

/// The Profile tab — the pilot's hub: identity, Pro status, vehicle garage,
/// lifetime telemetry, and the menu into friends, groups and settings.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// A vehicle the user picked but hasn't deployed yet.
  String? _pendingVehicle;
  bool _switching = false;

  Future<void> _signOut() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You can sign back in any time.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    try {
      // Forget this device's push token while the session is still valid, so a
      // signed-out device stops receiving this account's notifications.
      await unregisterPush();
      await SupabaseService.auth.signOut();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _switchVehicle(Profile profile, String id) async {
    setState(() => _switching = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(profile.copyWith(vehicleType: id));
      ref.invalidate(myProfileProvider);
      if (mounted) {
        setState(() => _pendingVehicle = null);
        showAppToast(context, 'Active vehicle updated.');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return BrandScaffold(
      bottomSafeArea: false,
      header: const _ProfileBar(),
      child: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Text(
                'No profile found.',
                style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            children: [
              _ProfileHeaderCard(profile: profile),
              const SizedBox(height: BrandSpace.md),
              _ProCard(isPro: ref.watch(isProProvider)),
              const SizedBox(height: BrandSpace.lg),
              _VehicleGarage(
                profile: profile,
                selected: _pendingVehicle ?? profile.vehicleType,
                switching: _switching,
                onSelect: (id) => setState(() => _pendingVehicle = id),
                onSwitch: () => _switchVehicle(profile, _pendingVehicle!),
              ),
              const SizedBox(height: BrandSpace.lg),
              const _PilotRollup(),
              const SizedBox(height: BrandSpace.lg),
              const _MenuCard(),
              const SizedBox(height: BrandSpace.lg),
              _SignOutFooter(onSignOut: _signOut),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
      ),
    );
  }
}

/// The brand app bar: identity mark on the left, settings on the right.
class _ProfileBar extends StatelessWidget {
  const _ProfileBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(bottom: BorderSide(color: BrandColors.hairline)),
      ),
      child: Row(
        children: [
          const BrandMarkGlyph(),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'RanMap',
                    style: BrandText.weight(
                      BrandText.titleSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: BrandColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              Text(
                'Profile',
                style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.settings_rounded,
                size: 20,
                color: BrandColors.textHeadline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The little brand tile in the app bar.
class BrandMarkGlyph extends StatelessWidget {
  const BrandMarkGlyph({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.primaryContainer, BrandColors.primary],
        ),
      ),
      child: Icon(
        Icons.navigation_rounded,
        size: size * 0.55,
        color: BrandColors.onPrimary,
      ),
    );
  }
}

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final private = ref.watch(myPrivateProfileProvider).valueOrNull;
    final vehicle = vehicleDisplay(profile.vehicleType);
    final name = profile.displayName?.trim().isNotEmpty ?? false
        ? profile.displayName!.trim()
        : profile.username;

    return BrandCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BrandRadii.podRadius,
        child: Stack(
          children: [
            // Ambient pastel glow, clipped to the card's rounded bounds.
            Positioned(
              top: -48,
              right: -48,
              child: _Glow(
                color: BrandColors.accentMint.withValues(alpha: 0.3),
                size: 176,
              ),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: _Glow(
                color: BrandColors.accentPeach.withValues(alpha: 0.25),
                size: 144,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BrandSpace.lg),
              child: Column(
                children: [
                  Container(
                    height: 96,
                    width: 96,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BrandColors.surfaceContainerLow,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BrandColors.primaryFixedDim,
                            BrandColors.accentSky,
                            BrandColors.accentPeach,
                          ],
                        ),
                      ),
                      child: AvatarView(
                        seed: profile.avatarId,
                        size: 84,
                        background: BrandColors.surface,
                      ),
                    ),
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.headlineMd.copyWith(
                            color: BrandColors.textHeadline,
                          ),
                        ),
                      ),
                      if (private?.phoneVerified == true) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified_rounded,
                          size: 20,
                          color: BrandColors.primaryContainer,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '@${profile.username}',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _VehiclePill(vehicle: vehicle),
                  const SizedBox(height: BrandSpace.md),
                  _SocialChips(profile: profile, private: private),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 48, spreadRadius: 8)],
      ),
    ),
  );
}

class _VehiclePill extends StatelessWidget {
  const _VehiclePill({required this.vehicle});

  final VehicleDisplay vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.secondaryFixed.withValues(alpha: 0.4),
        borderRadius: BrandRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_car_rounded,
            size: 15,
            color: BrandColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            vehicle.title,
            style: BrandText.labelSm.copyWith(
              color: BrandColors.onSecondaryFixedVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialChips extends StatelessWidget {
  const _SocialChips({required this.profile, required this.private});

  final Profile profile;
  final ({
    String? phoneNumber,
    Map<String, String> socials,
    bool phoneVerified,
  })?
  private;

  @override
  Widget build(BuildContext context) {
    final socials = private?.socials ?? const <String, String>{};
    final phone = private?.phoneNumber;
    final phoneVerified = private?.phoneVerified == true;
    void openSocials() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LinkedSocialsScreen()));
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        _Chip(
          icon: phoneVerified
              ? Icons.check_circle_rounded
              : Icons.add_circle_outline_rounded,
          iconColor: phoneVerified
              ? BrandColors.primaryContainer
              : BrandColors.textMuted,
          label: phone != null ? _maskPhone(phone) : 'Add number',
          onTap: openSocials,
        ),
        _Chip(
          icon: Icons.alternate_email_rounded,
          iconColor: BrandColors.textMuted,
          label: profile.username,
        ),
        for (final entry in socials.entries)
          _Chip(
            icon: Icons.link_rounded,
            iconColor: BrandColors.textMuted,
            label: _socialLabel(entry.key),
            onTap: openSocials,
          ),
      ],
    );
  }

  static String _socialLabel(String key) => switch (key) {
    'x' => 'X',
    'instagram' => 'Instagram',
    'tiktok' => 'TikTok',
    _ => key,
  };
}

/// Masks all but the last four digits, e.g. `+1 555-***-0194`.
String _maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 4) return phone;
  return '${phone.substring(0, phone.length - 4)}****${phone.substring(phone.length - 4)}';
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: BrandText.labelSm.copyWith(color: BrandColors.textHeadline),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }
}

class _ProCard extends ConsumerWidget {
  const _ProCard({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expires = ref.watch(entitlementsProvider).valueOrNull?.expiresAt;
    final subtitle = isPro
        ? (expires != null
              ? 'Renews ${DateFormat('MMM yyyy').format(expires)}'
              : 'Active subscription')
        : 'Unlock AI, voice & unlimited search';

    return GestureDetector(
      onTap: isPro ? null : () => context.push('/paywall'),
      behavior: HitTestBehavior.opaque,
      child: BrandCard(
        padding: const EdgeInsets.all(BrandSpace.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isPro
              ? [BrandColors.surface, BrandColors.secondaryFixed]
              : [BrandColors.surface, BrandColors.surfaceContainerLow],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: isPro
                        ? BrandColors.primaryContainer
                        : BrandColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.stars_rounded,
                    size: 20,
                    color: isPro
                        ? BrandColors.onPrimary
                        : BrandColors.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'RanMap Pro',
                            style: BrandText.weight(
                              BrandText.titleSm,
                              700,
                            ).copyWith(color: BrandColors.textHeadline),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            height: 6,
                            width: 6,
                            decoration: BoxDecoration(
                              color: BrandColors.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isPro ? 'Active Member' : 'Free plan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BrandText.labelSm.copyWith(
                                color: BrandColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.bodySm.copyWith(
                          color: BrandColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.verified_user_rounded,
                  size: 18,
                  color: BrandColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BrandColors.surface.withValues(alpha: 0.9),
                borderRadius: BrandRadii.miniRadius,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.offline_bolt_rounded,
                    size: 18,
                    color: BrandColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.textHeadline,
                        ),
                        children: [
                          TextSpan(
                            text: isPro
                                ? 'UNLIMITED ACCESS: '
                                : 'UPGRADE FOR: ',
                            style: BrandText.weight(
                              BrandText.labelSm,
                              700,
                            ).copyWith(color: BrandColors.primary),
                          ),
                          const TextSpan(
                            text: 'AI Assistant, LiveKit Audio & 3D Terrain',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleGarage extends StatelessWidget {
  const _VehicleGarage({
    required this.profile,
    required this.selected,
    required this.switching,
    required this.onSelect,
    required this.onSwitch,
  });

  final Profile profile;
  final String selected;
  final bool switching;
  final ValueChanged<String> onSelect;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final changed = selected != profile.vehicleType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandSectionHeader(
          icon: Icons.garage_rounded,
          title: 'Vehicle Garage',
          trailing: BrandPill(label: '${kVehicleOptions.length} Ready'),
        ),
        const SizedBox(height: BrandSpace.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: BrandSpace.gutterSm,
          crossAxisSpacing: BrandSpace.gutterSm,
          childAspectRatio: 0.95,
          children: [
            for (final option in kVehicleOptions)
              _GarageTile(
                display: vehicleDisplay(option.id),
                selected: selected == option.id,
                onTap: () => onSelect(option.id),
              ),
          ],
        ),
        const SizedBox(height: BrandSpace.md),
        Opacity(
          opacity: changed ? 1 : 0.5,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: BrandColors.primaryContainer,
              borderRadius: BrandRadii.pill,
              boxShadow: BrandShadows.primaryGlow,
            ),
            child: TextButton.icon(
              onPressed: (changed && !switching) ? onSwitch : null,
              icon: switching
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: BrandColors.onPrimary,
                      ),
                    )
                  : Icon(
                      changed
                          ? Icons.swap_horiz_rounded
                          : Icons.check_circle_rounded,
                      color: BrandColors.onPrimary,
                      size: 20,
                    ),
              label: Text(
                changed ? 'Switch Active Vehicle' : 'Active Vehicle',
                style: BrandText.weight(
                  BrandText.labelLg,
                  700,
                ).copyWith(color: BrandColors.onPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GarageTile extends StatelessWidget {
  const _GarageTile({
    required this.display,
    required this.selected,
    required this.onTap,
  });

  final VehicleDisplay display;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BrandRadii.cardRadius,
          border: Border.all(
            color: selected ? BrandColors.primaryContainer : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected ? BrandShadows.pod : BrandShadows.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: 32,
                  width: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? BrandColors.primaryContainer
                        : BrandColors.surfaceContainerLow,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    display.icon,
                    size: 18,
                    color: selected
                        ? BrandColors.onPrimary
                        : BrandColors.textHeadline,
                  ),
                ),
                Container(
                  height: 24,
                  width: 24,
                  decoration: BoxDecoration(
                    color: selected
                        ? BrandColors.primaryContainer
                        : BrandColors.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    size: 15,
                    color: selected
                        ? BrandColors.onPrimary
                        : BrandColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _tintFor(display.icon),
                borderRadius: BrandRadii.miniRadius,
              ),
              child: Icon(display.icon, size: 34, color: BrandColors.primary),
            ),
            const Spacer(),
            Text(
              display.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.titleSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            Text(
              display.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.bodySm.copyWith(
                color: selected ? BrandColors.primary : BrandColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _tintFor(IconData icon) => switch (icon) {
    Icons.two_wheeler_rounded => BrandColors.accentPeach.withValues(alpha: 0.3),
    Icons.electric_car_rounded => BrandColors.accentSky.withValues(alpha: 0.3),
    Icons.electric_scooter_rounded => BrandColors.secondaryFixed.withValues(
      alpha: 0.3,
    ),
    _ => BrandColors.accentMint.withValues(alpha: 0.25),
  };
}

/// The free-plan state of the Pilot Rollup: the same header, locked, with an
/// upgrade path — rather than showing Pro numbers to a non-subscriber.
class _LockedRollup extends StatelessWidget {
  const _LockedRollup();

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionHeader(
            icon: Icons.timeline_rounded,
            title: 'Pilot Rollup',
            subtitle: 'Lifetime convoy telemetry',
            trailing: BrandPill(
              label: 'Pro',
              icon: Icons.lock_rounded,
              background: BrandColors.surfaceContainerHigh,
              foreground: BrandColors.onSurfaceVariant,
              iconColor: BrandColors.textMuted,
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          Text(
            'Lifetime distance, drive time and convoy counters are part of '
            'RanMap Pro, alongside AI assistance and unlimited trip history.',
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
          const SizedBox(height: BrandSpace.md),
          BrandPrimaryButton(
            label: 'Unlock Pro stats',
            leadingIcon: Icons.bolt_rounded,
            trailingIcon: null,
            onPressed: () => context.push('/paywall'),
          ),
        ],
      ),
    );
  }
}

class _PilotRollup extends ConsumerWidget {
  const _PilotRollup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lifetime telemetry is a Pro feature (PremiumFeature.history) — a free
    // pilot sees an upgrade card instead of the numbers.
    if (!ref.watch(isProProvider)) return const _LockedRollup();

    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final rows =
        ref.watch(myTripStatsProvider).valueOrNull ??
        const <Map<String, dynamic>>[];

    final totalKm = rows.fold<double>(
      0,
      (sum, r) => sum + ((r['total_distance_km'] as num?)?.toDouble() ?? 0),
    );
    final totalSeconds = rows.fold<int>(
      0,
      (sum, r) => sum + ((r['duration_seconds'] as num?)?.toInt() ?? 0),
    );
    final speeds = rows
        .map((r) => (r['avg_speed_kmh'] as num?)?.toDouble() ?? 0)
        .where((s) => s > 0)
        .toList();
    final avgSpeed = speeds.isEmpty
        ? 0.0
        : speeds.reduce((a, b) => a + b) / speeds.length;
    final recent = rows
        .take(8)
        .map((r) => (r['total_distance_km'] as num?)?.toDouble() ?? 0)
        .toList()
        .reversed
        .toList();
    final recentKm = recent.fold<double>(0, (a, b) => a + b);

    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionHeader(
            icon: Icons.timeline_rounded,
            title: 'Pilot Rollup',
            subtitle: 'Lifetime convoy telemetry',
            trailing: BrandPill(
              label: 'Pro Stats',
              icon: Icons.auto_graph_rounded,
              background: BrandColors.accentMint,
              foreground: BrandColors.onSecondaryFixedVariant,
              iconColor: BrandColors.primary,
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          Row(
            children: [
              Expanded(
                child: BrandStatTile(
                  label: 'Total Distance',
                  value: formatDistance(totalKm, unit, decimals: 0),
                  caption: 'navigated',
                  icon: Icons.route_rounded,
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              Expanded(
                child: BrandStatTile(
                  label: 'Drive Time',
                  value: _formatDuration(totalSeconds),
                  caption: 'behind the wheel',
                  icon: Icons.schedule_rounded,
                  iconColor: BrandColors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.sm),
          Row(
            children: [
              Expanded(
                child: BrandStatTile(
                  label: 'Convoys',
                  value: '${rows.length}',
                  caption: 'trips logged',
                  icon: Icons.flag_rounded,
                  iconColor: BrandColors.secondary,
                ),
              ),
              const SizedBox(width: BrandSpace.sm),
              Expanded(
                child: BrandStatTile(
                  label: 'Avg Speed',
                  value: formatSpeed(avgSpeed, unit),
                  caption: 'convoy cruise pace',
                  icon: Icons.speed_rounded,
                ),
              ),
            ],
          ),
          if (recent.length >= 2) ...[
            const SizedBox(height: BrandSpace.md),
            BrandSparklineRow(
              title: 'Recent Trips',
              caption:
                  '${recent.length} trips · ${formatDistance(recentKm, unit, decimals: 0)}',
              values: recent,
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0h 0m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return '${h}h ${m}m';
}

class _MenuCard extends ConsumerWidget {
  const _MenuCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming =
        ref.watch(incomingRequestsProvider).valueOrNull?.length ?? 0;
    final groups = ref.watch(myGroupsProvider).valueOrNull?.length ?? 0;
    final outbox = ref.watch(outboxProvider);

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.md),
      child: Column(
        children: [
          BrandListRow(
            icon: Icons.group_rounded,
            iconBackground: BrandColors.accentSky.withValues(alpha: 0.3),
            title: 'Friends & Crew',
            subtitle: 'Manage travel companions',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
            trailing: incoming > 0
                ? BrandPill(
                    label: '$incoming Pending',
                    background: BrandColors.accentPeach,
                    foreground: BrandColors.onTertiaryContainer,
                    bold: true,
                  )
                : null,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.diversity_3_rounded,
            iconBackground: BrandColors.secondaryFixed.withValues(alpha: 0.5),
            iconColor: BrandColors.secondary,
            title: 'Convoy Groups',
            subtitle: 'Your rolling crews',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GroupsScreen())),
            trailing: groups > 0 ? BrandPill(label: '$groups Groups') : null,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.tune_rounded,
            title: 'Preferences & Map Units',
            subtitle: 'Theme, units, map style & more',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            trailing: null,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.link_rounded,
            title: 'Linked socials',
            subtitle: 'Phone & social handles',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinkedSocialsScreen()),
            ),
            trailing: null,
          ),
          const BrandRowDivider(),
          BrandListRow(
            icon: Icons.bar_chart_rounded,
            title: 'Trip stats & history',
            subtitle: 'Every trip you have logged',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
            ),
            trailing: null,
          ),
          const BrandRowDivider(),
          ValueListenableBuilder<int>(
            valueListenable: outbox.pending,
            builder: (context, pending, _) => BrandListRow(
              icon: Icons.cloud_done_rounded,
              iconBackground: BrandColors.accentMint.withValues(alpha: 0.3),
              iconColor: BrandColors.primary,
              title: 'Offline Data & Queue',
              subtitle: pending == 0
                  ? 'Synced'
                  : '$pending pending write${pending == 1 ? '' : 's'}',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              trailing: Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: BrandColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutFooter extends StatelessWidget {
  const _SignOutFooter({required this.onSignOut});

  final VoidCallback onSignOut;

  /// Hoisted so the platform lookup runs once, not on every rebuild.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onSignOut,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 48,
            width: double.infinity,
            decoration: BoxDecoration(
              color: BrandColors.surfaceContainerLow,
              borderRadius: BrandRadii.pill,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, size: 18, color: BrandColors.error),
                const SizedBox(width: 8),
                Text(
                  'Sign Out',
                  style: BrandText.weight(
                    BrandText.labelMd,
                    700,
                  ).copyWith(color: BrandColors.error),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (context, snapshot) {
            final info = snapshot.data;
            if (info == null) return const SizedBox.shrink();
            return Text(
              'RanMap v${info.version} (Build ${info.buildNumber})',
              style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
            );
          },
        ),
      ],
    );
  }
}
