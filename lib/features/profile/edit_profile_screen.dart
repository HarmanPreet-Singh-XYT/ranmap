import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_editor.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late String _avatarSeed;
  late List<String> _avatarCandidates;

  /// A photo uploaded during this session that the profile doesn't reference
  /// yet (cleared once saved, or discarded if the user picks something else).
  String? _pendingUpload;
  bool _uploading = false;
  late String _vehicleType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.profile.username);
    _displayNameCtrl = TextEditingController(
      text: widget.profile.displayName ?? '',
    );
    _avatarSeed = widget.profile.avatarId;
    _avatarCandidates = avatarSeedCandidates(include: _avatarSeed);
    _vehicleType = widget.profile.vehicleType;
  }

  void _shuffleAvatars() {
    _discardPendingUpload();
    setState(() {
      _avatarSeed = randomAvatarSeed();
      _avatarCandidates = avatarSeedCandidates(include: _avatarSeed);
    });
  }

  /// Picks a photo (camera or library), uploads it, and selects it. The id is
  /// only persisted when the user saves.
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
      // Replacing a photo uploaded earlier in this session: drop the old file.
      if (previous != null) {
        unawaited(ref.read(avatarRepositoryProvider).remove(previous));
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Switches back to a generated avatar. The photo currently referenced by the
  /// profile is deleted only after the change is saved (see [_save]), so backing
  /// out without saving doesn't leave the profile pointing at a deleted file.
  void _useGeneratedAvatar() {
    _discardPendingUpload();
    setState(() {
      _avatarSeed = randomAvatarSeed();
      _avatarCandidates = avatarSeedCandidates(include: _avatarSeed);
    });
  }

  /// Drops a not-yet-saved upload when the user picks a generated avatar
  /// instead (leaving a small orphaned file is otherwise harmless).
  void _discardPendingUpload() {
    final pending = _pendingUpload;
    if (pending == null) return;
    _pendingUpload = null;
    unawaited(ref.read(avatarRepositoryProvider).remove(pending));
  }

  @override
  void dispose() {
    // Drop an unsaved upload so it doesn't linger in the avatars bucket.
    final pending = _pendingUpload;
    if (pending != null) {
      unawaited(ref.read(avatarRepositoryProvider).remove(pending));
    }
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final usernameValidationError = usernameError(username);
    if (usernameValidationError != null) {
      setState(() => _error = usernameValidationError);
      return;
    }
    final displayName = _displayNameCtrl.text.trim();
    if (displayName.length > kDisplayNameMaxLength) {
      setState(
        () => _error =
            'Display name must be $kDisplayNameMaxLength characters or fewer',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(profileRepositoryProvider);
    try {
      if (username.toLowerCase() != widget.profile.username.toLowerCase()) {
        final available = await repo.isUsernameAvailable(username);
        if (!available) {
          setState(() {
            _error = 'That username is taken';
            _saving = false;
          });
          return;
        }
      }

      await repo.updateProfile(
        widget.profile.copyWith(
          username: username,
          displayName: displayName.isEmpty ? null : displayName,
          avatarId: _avatarSeed,
          vehicleType: _vehicleType,
        ),
      );

      // Now that the write succeeded, clean up a replaced photo. Deleting it
      // before this point would break the profile if the user backed out.
      final originalCustomPath = isCustomAvatar(widget.profile.avatarId)
          ? customAvatarPath(widget.profile.avatarId)
          : null;
      final currentCustomPath = isCustomAvatar(_avatarSeed)
          ? customAvatarPath(_avatarSeed)
          : null;
      if (originalCustomPath != null &&
          originalCustomPath != currentCustomPath) {
        unawaited(
          ref.read(avatarRepositoryProvider).remove(originalCustomPath),
        );
      }

      ref.invalidate(myProfileProvider);
      // The uploaded photo is now referenced by the profile.
      _pendingUpload = null;
      if (mounted) Navigator.of(context).pop();
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
        title: 'Edit profile',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.xl,
        ),
        children: [
          BrandTextField(
            controller: _usernameCtrl,
            hint: 'Username',
            leadingIcon: Icons.alternate_email_rounded,
            maxLength: kUsernameMaxLength,
            inputFormatters: [
              FilteringTextInputFormatter.allow(kUsernameInputFormatter),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: BrandSpace.md),
          BrandTextField(
            controller: _displayNameCtrl,
            hint: 'Display name',
            leadingIcon: Icons.badge_outlined,
            maxLength: kDisplayNameMaxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: BrandSpace.sm),
          Text(
            'Optional — shown where there’s room, beside your @username.',
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(icon: Icons.face_rounded, title: 'Avatar'),
          const SizedBox(height: BrandSpace.md),
          AvatarEditor(
            avatarId: _avatarSeed,
            candidates: _avatarCandidates,
            uploading: _uploading,
            onUploadPhoto: _uploadPhoto,
            onRemovePhoto: isCustomAvatar(_avatarSeed)
                ? _useGeneratedAvatar
                : null,
            onSelectSeed: (seed) {
              _discardPendingUpload();
              setState(() => _avatarSeed = seed);
            },
            onShuffle: _shuffleAvatars,
          ),
          const SizedBox(height: BrandSpace.lg),
          const BrandSectionHeader(
            icon: Icons.directions_car_rounded,
            title: 'Vehicle',
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: Column(
              children: [
                for (final (i, vehicle) in kVehicleOptions.indexed) ...[
                  if (i > 0) const BrandRowDivider(),
                  BrandListRow(
                    icon: vehicleDisplay(vehicle.id).icon,
                    title: vehicle.label,
                    showChevron: false,
                    onTap: () => setState(() => _vehicleType = vehicle.id),
                    iconBackground: _vehicleType == vehicle.id
                        ? BrandColors.accentMint.withValues(alpha: 0.45)
                        : BrandColors.surfaceContainerLow,
                    iconColor: _vehicleType == vehicle.id
                        ? BrandColors.primary
                        : BrandColors.textHeadline,
                    trailing: _vehicleType == vehicle.id
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: 22,
                            color: BrandColors.primaryContainer,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.lg),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Save',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
