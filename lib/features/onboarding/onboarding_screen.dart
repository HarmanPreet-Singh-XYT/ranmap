import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/vehicle_display.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/image_upload.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_pod.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_step_indicator.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/services/supabase_service.dart';

/// Step 2 of the onboarding flow: the pilot handle, avatar and convoy vehicle.
/// Creates the `profiles` row, then hands off to phone verification.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Availability { unknown, checking, available, taken }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _handleCtrl = TextEditingController();
  late String _avatarSeed;
  late List<String> _avatarCandidates;

  /// A photo uploaded during this session that isn't saved to the profile yet.
  String? _pendingUpload;
  bool _uploading = false;
  String _selectedVehicle = kDefaultVehicleType;
  bool _saving = false;
  bool _skipping = false;
  String? _error;

  _Availability _availability = _Availability.unknown;
  Timer? _availabilityDebounce;
  int _availabilitySeq = 0;

  @override
  void initState() {
    super.initState();
    // Every new account gets a random avatar out of the box; the user can pick
    // a different one (or upload a photo) below.
    _avatarSeed = randomAvatarSeed();
    _avatarCandidates = avatarSeedCandidates(
      count: kPilotAvatarSlots,
      include: _avatarSeed,
    );
  }

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
    // Abandoning onboarding with an unsaved upload would otherwise orphan the
    // file in the avatars bucket.
    final pending = _pendingUpload;
    if (pending != null) {
      unawaited(ref.read(avatarRepositoryProvider).remove(pending));
    }
    _handleCtrl.dispose();
    super.dispose();
  }

  // --- Handle availability ---------------------------------------------------

  void _onHandleChanged(String value) {
    if (_error != null) setState(() => _error = null);
    _availabilityDebounce?.cancel();

    if (usernameError(value) != null) {
      setState(() => _availability = _Availability.unknown);
      return;
    }

    setState(() => _availability = _Availability.checking);
    final seq = ++_availabilitySeq;
    _availabilityDebounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final available = await ref
            .read(profileRepositoryProvider)
            .isUsernameAvailable(value.trim());
        if (!mounted || seq != _availabilitySeq) return;
        setState(
          () => _availability = available
              ? _Availability.available
              : _Availability.taken,
        );
      } catch (_) {
        if (mounted && seq == _availabilitySeq) {
          setState(() => _availability = _Availability.unknown);
        }
      }
    });
  }

  // --- Avatar ----------------------------------------------------------------

  void _shuffleAvatars() {
    _discardPendingUpload();
    setState(() {
      _avatarSeed = randomAvatarSeed();
      _avatarCandidates = avatarSeedCandidates(
        count: kPilotAvatarSlots,
        include: _avatarSeed,
      );
    });
  }

  /// Picks a photo (camera or library) and uploads it; the profile is written
  /// on Continue.
  Future<void> _uploadPhoto() async {
    final source = await showAppChoiceSheet<ImageSource>(
      context,
      title: 'Profile photo',
      options: const [
        (value: ImageSource.camera, label: 'Take a photo'),
        (value: ImageSource.gallery, label: 'Choose from library'),
      ],
    );
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    final previous = _pendingUpload;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final extension = imageExtensionOf(file.name);

      final path = await ref
          .read(avatarRepositoryProvider)
          .upload(bytes: bytes, fileExtension: extension);
      if (!mounted) return;
      setState(() {
        _pendingUpload = path;
        _avatarSeed = customAvatarId(path);
      });
      if (previous != null) {
        unawaited(ref.read(avatarRepositoryProvider).remove(previous));
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Drops a not-yet-saved upload when a generated avatar is chosen instead.
  void _discardPendingUpload() {
    final pending = _pendingUpload;
    if (pending == null) return;
    _pendingUpload = null;
    unawaited(ref.read(avatarRepositoryProvider).remove(pending));
  }

  // --- Finish ----------------------------------------------------------------

  Future<void> _continue() async {
    final handle = _handleCtrl.text.trim();
    final validationError = usernameError(handle);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    await _createProfile(handle);
  }

  /// "Skip" takes the sensible defaults: a generated handle, the random avatar
  /// already shown, and the default vehicle.
  Future<void> _skip() async {
    if (_saving || _skipping) return;
    // Guard immediately: generating a handle is up to 5 network round-trips, and
    // without this the Skip button stays tappable and can launch a second,
    // racing profile create.
    setState(() => _skipping = true);
    try {
      final handle = await _generateAvailableHandle();
      if (!mounted) return;
      if (handle == null) {
        setState(
          () => _error = 'Could not reserve a handle — enter one manually',
        );
        return;
      }
      _handleCtrl.text = handle;
      setState(() => _availability = _Availability.available);
      await _createProfile(handle);
    } finally {
      if (mounted) setState(() => _skipping = false);
    }
  }

  Future<String?> _generateAvailableHandle() async {
    final repo = ref.read(profileRepositoryProvider);
    for (var i = 0; i < 5; i++) {
      final candidate = 'rider_${randomAvatarSeed().substring(0, 6)}';
      try {
        if (await repo.isUsernameAvailable(candidate)) return candidate;
      } catch (_) {
        // Can't confirm availability right now (network/transient). Don't hand
        // back an unverified handle that would race into a PK conflict — surface
        // it instead so the user can type one.
        return null;
      }
    }
    return null;
  }

  Future<void> _createProfile(String handle) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(profileRepositoryProvider);
    try {
      final available = await repo.isUsernameAvailable(handle);
      if (!available) {
        setState(() {
          _error = 'That username is taken';
          _saving = false;
          _availability = _Availability.taken;
        });
        return;
      }

      await repo.createProfile(
        Profile(
          id: SupabaseService.currentUserId,
          username: handle,
          avatarId: _avatarSeed,
          vehicleType: _selectedVehicle,
        ),
      );
      // Any uploaded photo is now referenced by the profile.
      _pendingUpload = null;

      // Navigate before invalidating: the redirect is allowed to sit on
      // /verify-phone, whereas a still-cached "no profile" would bounce us back
      // to /onboarding if we invalidated first.
      if (!mounted) return;
      context.go('/verify-phone');
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Vehicle Setup',
        showBack: false,
        onSkip: (_saving || _skipping) ? null : _skip,
        showAvatar: true,
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.lg,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const BrandStepPill(label: 'Step 2 of 3'),
              const BrandSegmentStepper(count: 3, index: 1),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          Text(
            'Set up your pilot profile',
            style: BrandText.headlineLg.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how you appear to your convoy crew.',
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
          const SizedBox(height: BrandSpace.lg),
          _HandleSection(
            controller: _handleCtrl,
            availability: _availability,
            onChanged: _onHandleChanged,
          ),
          const SizedBox(height: BrandSpace.lg),
          _AvatarSection(
            avatarSeed: _avatarSeed,
            candidates: _avatarCandidates,
            uploading: _uploading,
            onSelectSeed: (seed) {
              _discardPendingUpload();
              setState(() => _avatarSeed = seed);
            },
            onUploadPhoto: _uploadPhoto,
            onShuffle: _shuffleAvatars,
          ),
          const SizedBox(height: BrandSpace.xl),
          _VehicleSection(
            selected: _selectedVehicle,
            onSelect: (id) => setState(() => _selectedVehicle = id),
          ),
          const SizedBox(height: BrandSpace.lg),
          const _AutoSyncBanner(),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Continue to Verification',
            loading: _saving,
            onPressed: _continue,
          ),
          const SizedBox(height: 12),
          Text(
            'You can update vehicle specs anytime before convoy launch.',
            textAlign: TextAlign.center,
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
        ],
      ),
    );
  }
}

const int kPilotAvatarSlots = 5;

/// Friendly names for the generated avatar slots (decorative).
const List<String> _pilotRoleNames = [
  'Scout',
  'Navigator',
  'Cruiser',
  'Roamer',
  'Voyager',
];

class _HandleSection extends StatelessWidget {
  const _HandleSection({
    required this.controller,
    required this.availability,
    required this.onChanged,
  });

  final TextEditingController controller;
  final _Availability availability;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pilot Handle',
                style: BrandText.labelMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.verified_rounded,
              size: 14,
              color: BrandColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Supabase Auth Verified',
              style: BrandText.labelSm.copyWith(color: BrandColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BrandTextField(
          controller: controller,
          hint: 'your_handle',
          leadingIcon: Icons.alternate_email_rounded,
          radius: BrandRadii.pill,
          style: BrandText.labelLg,
          autofillHints: const [AutofillHints.newUsername],
          maxLength: kUsernameMaxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(kUsernameInputFormatter),
          ],
          onChanged: onChanged,
          trailing: _AvailabilityChip(availability: availability),
        ),
      ],
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.availability});

  final _Availability availability;

  @override
  Widget build(BuildContext context) {
    switch (availability) {
      case _Availability.unknown:
        return const SizedBox(width: 8);
      case _Availability.checking:
        return const Padding(
          padding: EdgeInsets.only(right: 6),
          child: SizedBox(height: 16, width: 16, child: AppSpinner()),
        );
      case _Availability.available:
        return _chip(
          bg: BrandColors.secondaryFixed,
          fg: BrandColors.onSecondaryFixed,
          icon: Icons.check_circle_rounded,
          label: 'Available',
        );
      case _Availability.taken:
        return _chip(
          bg: BrandColors.errorContainer,
          fg: BrandColors.onErrorContainer,
          icon: Icons.cancel_rounded,
          label: 'Taken',
        );
    }
  }

  Widget _chip({
    required Color bg,
    required Color fg,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BrandRadii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label, style: BrandText.labelSm.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  const _AvatarSection({
    required this.avatarSeed,
    required this.candidates,
    required this.uploading,
    required this.onSelectSeed,
    required this.onUploadPhoto,
    required this.onShuffle,
  });

  final String avatarSeed;
  final List<String> candidates;
  final bool uploading;
  final ValueChanged<String> onSelectSeed;
  final VoidCallback onUploadPhoto;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final customSelected = isCustomAvatar(avatarSeed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pilot Avatar',
              style: BrandText.labelMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            GestureDetector(
              onTap: onShuffle,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    Icons.shuffle_rounded,
                    size: 14,
                    color: BrandColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Shuffle',
                    style: BrandText.labelSm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            children: [
              for (var i = 0; i < candidates.length; i++)
                _AvatarOption(
                  seed: candidates[i],
                  label: _pilotRoleNames[i % _pilotRoleNames.length],
                  selected: !customSelected && avatarSeed == candidates[i],
                  onTap: () => onSelectSeed(candidates[i]),
                ),
              _CustomAvatarOption(
                avatarSeed: avatarSeed,
                uploading: uploading,
                selected: customSelected,
                onTap: onUploadPhoto,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    required this.seed,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String seed;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Ring(
              selected: selected,
              child: AvatarView(
                seed: seed,
                size: 64,
                background: BrandColors.surfaceContainerLow,
                accentColor: BrandColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: BrandText.labelSm.copyWith(
                color: selected ? BrandColors.primary : BrandColors.textMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomAvatarOption extends StatelessWidget {
  const _CustomAvatarOption({
    required this.avatarSeed,
    required this.uploading,
    required this.selected,
    required this.onTap,
  });

  final String avatarSeed;
  final bool uploading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Ring(
              selected: selected,
              child: selected
                  ? AvatarView(
                      seed: avatarSeed,
                      size: 64,
                      background: BrandColors.surfaceContainerLow,
                      accentColor: BrandColors.primary,
                    )
                  : Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: BrandColors.neutralButton,
                        shape: BoxShape.circle,
                      ),
                      child: uploading
                          ? const Center(child: AppSpinner())
                          : Icon(
                              Icons.add_a_photo_rounded,
                              size: 22,
                              color: BrandColors.textHeadline,
                            ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'Custom',
              style: BrandText.labelSm.copyWith(
                color: selected ? BrandColors.primary : BrandColors.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The green selection ring wrapper around an avatar slot.
class _Ring extends StatelessWidget {
  const _Ring({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? BrandColors.primary : Colors.transparent,
          ),
          child: child,
        ),
        if (selected)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                color: BrandColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 14,
                color: BrandColors.onPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

class _VehicleSection extends StatelessWidget {
  const _VehicleSection({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Convoy Vehicle',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.textHeadline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Calculates telemetry & convoy pacing',
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: BrandColors.accentMint.withValues(alpha: 0.5),
                borderRadius: BrandRadii.pill,
              ),
              child: Text(
                'Adaptive',
                style: BrandText.labelSm.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: BrandSpace.gutterSm,
          crossAxisSpacing: BrandSpace.gutterSm,
          childAspectRatio: 1.35,
          children: [
            for (final option in kVehicleOptions)
              _VehicleCard(
                style: vehicleDisplay(option.id),
                selected: selected == option.id,
                onTap: () => onSelect(option.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final VehicleDisplay style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrandPressable(
      onTap: onTap,
      borderRadius: BrandRadii.podRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(BrandSpace.md),
        decoration: BoxDecoration(
          color: selected
              ? BrandColors.secondaryFixed.withValues(alpha: 0.4)
              : BrandColors.canvas,
          borderRadius: BrandRadii.podRadius,
          border: Border.all(
            color: selected ? BrandColors.primary : BrandColors.hairline,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? BrandShadows.ambient : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? BrandColors.primaryContainer
                        : BrandColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: BrandShadows.subtle,
                  ),
                  child: Icon(
                    style.icon,
                    size: 22,
                    color: selected
                        ? BrandColors.onPrimary
                        : BrandColors.textHeadline,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 20,
                  width: 20,
                  decoration: BoxDecoration(
                    color: selected
                        ? BrandColors.primary
                        : BrandColors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: BrandColors.onPrimary,
                        )
                      : null,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.titleSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  style.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.labelSm.copyWith(
                    color: selected
                        ? BrandColors.onSecondaryFixedVariant
                        : BrandColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoSyncBanner extends StatelessWidget {
  const _AutoSyncBanner();

  @override
  Widget build(BuildContext context) {
    return BrandPod(
      color: BrandColors.accentPeach.withValues(alpha: 0.35),
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: BrandColors.surface,
              shape: BoxShape.circle,
              boxShadow: BrandShadows.subtle,
            ),
            child: Icon(
              Icons.sync_alt_rounded,
              size: 22,
              color: BrandColors.tertiary,
            ),
          ),
          const SizedBox(width: BrandSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Sync Convoy Pace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.labelMd.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
                Text(
                  'Matches stopping intervals to minimum range',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
                ),
              ],
            ),
          ),
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
    );
  }
}
