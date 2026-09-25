import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../constants/avatars.dart';
import '../theme/nav_palette.dart';
import 'app_spinner.dart';
import 'avatar_picker.dart';
import 'avatar_view.dart';

/// Preview + actions for choosing a profile picture: upload your own photo, or
/// pick a generated Multiavatar.
///
/// Purely presentational — the caller owns the state and performs the upload,
/// so this can be shared without either screen depending on the other.
class AvatarEditor extends StatelessWidget {
  const AvatarEditor({
    super.key,
    required this.avatarId,
    required this.candidates,
    required this.onSelectSeed,
    required this.onShuffle,
    this.onUploadPhoto,
    this.onRemovePhoto,
    this.uploading = false,
  });

  /// Either a Multiavatar seed or a `custom:<path>` id.
  final String avatarId;
  final List<String> candidates;
  final ValueChanged<String> onSelectSeed;
  final VoidCallback onShuffle;

  /// Omitted where uploading isn't offered.
  final VoidCallback? onUploadPhoto;

  /// Only offered while an uploaded photo is selected.
  final VoidCallback? onRemovePhoto;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final custom = isCustomAvatar(avatarId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: AvatarView(seed: avatarId, size: 96)),
        const SizedBox(height: 16),
        if (onUploadPhoto != null)
          FButton(
            variant: .outline,
            onPress: uploading ? null : onUploadPhoto,
            prefix: uploading ? const AppSpinner() : const Icon(Icons.add_a_photo_outlined),
            child: Text(uploading ? 'Uploading…' : (custom ? 'Change photo' : 'Upload a photo')),
          ),
        if (custom && onRemovePhoto != null) ...[
          const SizedBox(height: 6),
          FButton(
            variant: .ghost,
            onPress: uploading ? null : onRemovePhoto,
            child: const Text('Use a generated avatar'),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Or pick a generated avatar',
          style: TextStyle(fontSize: 13, color: c.mutedForeground),
        ),
        const SizedBox(height: 10),
        AvatarPicker(
          candidates: candidates,
          selected: avatarId,
          onSelect: onSelectSeed,
          onShuffle: onShuffle,
        ),
      ],
    );
  }
}
