import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_toast.dart';
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

  const AddMapPostScreen({super.key, required this.tripId, required this.lat, required this.lng});

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
      final file = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1920);
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
      final extension = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      await ref.read(mapPostRepositoryProvider).createPost(
            imageBytes: bytes,
            fileExtension: extension,
            lat: widget.lat,
            lng: widget.lng,
            caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
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
    final c = NavColors.of(context);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Pin a photo'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _picked == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_a_photo_outlined, size: 56, color: c.mutedForeground),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FButton(
                                variant: .outline,
                                onPress: () => _pick(ImageSource.camera),
                                prefix: const Icon(Icons.camera_alt_outlined),
                                child: const Text('Camera'),
                              ),
                              const SizedBox(width: 12),
                              FButton(
                                variant: .outline,
                                onPress: () => _pick(ImageSource.gallery),
                                prefix: const Icon(Icons.photo_library_outlined),
                                child: const Text('Gallery'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(File(_picked!.path), fit: BoxFit.cover, width: double.infinity),
                    ),
            ),
            const SizedBox(height: 14),
            FTextField(
              control: FTextFieldControl.managed(controller: _captionController),
              label: const Text('Caption (optional)'),
              hint: 'Say something about this spot',
              maxLines: 3,
              maxLength: 200,
            ),
            const SizedBox(height: 8),
            FButton(
              size: .lg,
              onPress: _picked == null || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: AppSpinner(color: Colors.white),
                    )
                  : const Text('Pin to map'),
            ),
          ],
        ),
      ),
    );
  }
}
