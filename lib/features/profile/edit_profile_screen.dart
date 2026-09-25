import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_editor.dart';
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
    _displayNameCtrl = TextEditingController(text: widget.profile.displayName ?? '');
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
      final extension = file.name.contains('.') ? file.name.split('.').last : 'jpg';

      final path = await ref.read(avatarRepositoryProvider).upload(
            bytes: bytes,
            fileExtension: extension,
          );
      if (!mounted) return;
      setState(() {
        _pendingUpload = path;
        _avatarSeed = customAvatarId(path);
      });
      // Replacing a photo uploaded earlier in this session: drop the old file.
      if (previous != null) unawaited(ref.read(avatarRepositoryProvider).remove(previous));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Switches back to a generated avatar, deleting the uploaded photo. A photo
  /// uploaded but not yet saved is simply dropped.
  void _useGeneratedAvatar() {
    final pending = _pendingUpload;
    final current = _avatarSeed;
    if (pending != null) {
      unawaited(ref.read(avatarRepositoryProvider).remove(pending));
    } else if (isCustomAvatar(current)) {
      unawaited(ref.read(avatarRepositoryProvider).remove(customAvatarPath(current)));
    }
    setState(() {
      _pendingUpload = null;
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
      setState(() => _error = 'Display name must be $kDisplayNameMaxLength characters or fewer');
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

      await repo.updateProfile(widget.profile.copyWith(
        username: username,
        displayName: displayName.isEmpty ? null : displayName,
        avatarId: _avatarSeed,
        vehicleType: _vehicleType,
      ));
      ref.invalidate(myProfileProvider);
      // The uploaded photo is now referenced by the profile.
      _pendingUpload = null;
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = friendlyError(e));
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
        title: const Text('Edit profile'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FTextField(
            control: FTextFieldControl.managed(
              controller: _usernameCtrl,
              onChange: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            label: const Text('Username'),
            maxLength: kUsernameMaxLength,
            inputFormatters: [FilteringTextInputFormatter.allow(kUsernamePattern)],
          ),
          const SizedBox(height: 16),
          FTextField(
            control: FTextFieldControl.managed(
              controller: _displayNameCtrl,
              onChange: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            label: const Text('Display name'),
            hint: 'Your name',
            description: const Text('Optional — shown where there’s room, beside your @username.'),
            maxLength: kDisplayNameMaxLength,
          ),
          const SizedBox(height: 28),
          Text('Avatar', style: _section(c)),
          const SizedBox(height: 14),
          AvatarEditor(
            avatarId: _avatarSeed,
            candidates: _avatarCandidates,
            uploading: _uploading,
            onUploadPhoto: _uploadPhoto,
            onRemovePhoto: isCustomAvatar(_avatarSeed) ? _useGeneratedAvatar : null,
            onSelectSeed: (seed) {
              _discardPendingUpload();
              setState(() => _avatarSeed = seed);
            },
            onShuffle: _shuffleAvatars,
          ),
          const SizedBox(height: 28),
          FSelectGroup<String>(
            label: const Text('Vehicle'),
            control: FMultiValueControl<String>.managedRadio(
              initial: _vehicleType,
              onChange: (values) {
                if (values.isNotEmpty) setState(() => _vehicleType = values.first);
              },
            ),
            children: [
              for (final vehicle in kVehicleOptions)
                FSelectGroupItemMixin.radio<String>(
                  value: vehicle.id,
                  label: Text(vehicle.label),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            FAlert(variant: .destructive, title: Text(_error!)),
          ],
          const SizedBox(height: 28),
          FButton(
            size: .lg,
            onPress: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: AppSpinner(color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  TextStyle _section(NavColors c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground);
}
