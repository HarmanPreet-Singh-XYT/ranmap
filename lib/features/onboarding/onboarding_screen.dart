import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../data/services/supabase_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _usernameCtrl = TextEditingController();
  late String _avatarSeed;
  late List<String> _avatarCandidates;

  /// A photo uploaded during this session that isn't saved to the profile yet.
  String? _pendingUpload;
  bool _uploading = false;
  String _selectedVehicle = kVehicleOptions.first.id;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Every new account gets a random avatar out of the box; the user can pick
    // a different one (or shuffle) below.
    _avatarSeed = randomAvatarSeed();
    _avatarCandidates = avatarSeedCandidates(include: _avatarSeed);
  }

  void _shuffleAvatars() {
    _discardPendingUpload();
    setState(() {
      _avatarSeed = randomAvatarSeed();
      _avatarCandidates = avatarSeedCandidates(include: _avatarSeed);
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
      if (previous != null) unawaited(ref.read(avatarRepositoryProvider).remove(previous));
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Switches back to a generated avatar, deleting the uploaded photo.
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

  /// Drops a not-yet-saved upload when a generated avatar is chosen instead.
  void _discardPendingUpload() {
    final pending = _pendingUpload;
    if (pending == null) return;
    _pendingUpload = null;
    unawaited(ref.read(avatarRepositoryProvider).remove(pending));
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final username = _usernameCtrl.text.trim();
    final validationError = usernameError(username);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(profileRepositoryProvider);
    try {
      final available = await repo.isUsernameAvailable(username);
      if (!available) {
        setState(() {
          _error = 'That username is taken';
          _saving = false;
        });
        return;
      }

      final uid = SupabaseService.currentUserId;
      await repo.createProfile(Profile(
        id: uid,
        username: username,
        avatarId: _avatarSeed,
        vehicleType: _selectedVehicle,
      ));
      ref.invalidate(myProfileProvider);
      // Any uploaded photo is now referenced by the profile.
      _pendingUpload = null;
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
      header: FHeader(title: const Text('Set up your profile')),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text('Choose a username', style: _section(c)),
          const SizedBox(height: 10),
          FTextField(
            control: FTextFieldControl.managed(
              controller: _usernameCtrl,
              onChange: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            label: const Text('Username'),
            hint: 'yourname',
            maxLength: kUsernameMaxLength,
            inputFormatters: [FilteringTextInputFormatter.allow(kUsernamePattern)],
          ),
          const SizedBox(height: 28),
          Text('Pick your avatar', style: _section(c)),
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
              initial: _selectedVehicle,
              onChange: (values) {
                if (values.isNotEmpty) setState(() => _selectedVehicle = values.first);
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
            onPress: _saving ? null : _finish,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: AppSpinner(color: Colors.white),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  TextStyle _section(NavColors c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground);
}