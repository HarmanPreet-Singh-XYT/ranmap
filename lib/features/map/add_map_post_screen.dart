import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/image_upload.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'map_post_providers.dart';

/// Capture or pick a photo and pin it to the current location on the trip's
/// map. Visibility defaults to 'group' (visible to trip participants) — see
/// can_view_map_post in 0002_rls_hardening.sql.
class AddMapPostScreen extends ConsumerStatefulWidget {
  final String tripId;
  final double lat;
  final double lng;

  const AddMapPostScreen({
    super.key,
    required this.tripId,
    required this.lat,
    required this.lng,
  });

  @override
  ConsumerState<AddMapPostScreen> createState() => _AddMapPostScreenState();
}

class _AddMapPostScreenState extends ConsumerState<AddMapPostScreen> {
  final _captionController = TextEditingController();
  XFile? _picked;
  bool _saving = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (file != null && mounted) setState(() => _picked = file);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _save() async {
    final picked = _picked;
    if (picked == null || _saving) return;

    setState(() => _saving = true);
    try {
      final bytes = await picked.readAsBytes();
      final extension = imageExtensionOf(picked.name);
      await ref
          .read(mapPostRepositoryProvider)
          .createPost(
            imageBytes: bytes,
            fileExtension: extension,
            lat: widget.lat,
            lng: widget.lng,
            caption: _captionController.text.trim().isEmpty
                ? null
                : _captionController.text.trim(),
            tripId: widget.tripId,
            visibility: ref.read(appSettingsProvider).photoVisibility,
          );
      ref.invalidate(tripMapPostsProvider(widget.tripId));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Over the free photo cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.photos);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Pin a photo',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.md,
        ),
        child: Column(
          children: [
            Expanded(
              child: _picked == null
                  ? Center(
                      child: BrandEmptyState(
                        icon: Icons.add_a_photo_outlined,
                        title: 'Add a photo',
                        message: 'Shoot a new photo or pick one from your library to pin to this spot.',
                        action: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BrandSecondaryButton(
                              label: 'Camera',
                              expand: false,
                              leading: Icon(
                                Icons.camera_alt_outlined,
                                size: 20,
                                color: BrandColors.textHeadline,
                              ),
                              onPressed: () => _pick(ImageSource.camera),
                            ),
                            const SizedBox(width: BrandSpace.sm),
                            BrandSecondaryButton(
                              label: 'Gallery',
                              expand: false,
                              leading: Icon(
                                Icons.photo_library_outlined,
                                size: 20,
                                color: BrandColors.textHeadline,
                              ),
                              onPressed: () => _pick(ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BrandRadii.podRadius,
                      child: Image.file(
                        File(_picked!.path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),
            const SizedBox(height: BrandSpace.md),
            BrandTextField(
              controller: _captionController,
              hint: 'Caption (optional)',
              leadingIcon: Icons.chat_bubble_outline_rounded,
              maxLength: 200,
              maxLines: 3,
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandPrimaryButton(
              label: 'Pin to map',
              leadingIcon: Icons.push_pin_rounded,
              loading: _saving,
              onPressed: _picked == null || _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
