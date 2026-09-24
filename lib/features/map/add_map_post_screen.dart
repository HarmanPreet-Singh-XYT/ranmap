import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/util/error_text.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
          );
      ref.invalidate(tripMapPostsProvider(widget.tripId));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Over the free photo cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.photos);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin a photo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _picked == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _pick(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Camera'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () => _pick(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Gallery'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_picked!.path), fit: BoxFit.cover, width: double.infinity),
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: 'Caption (optional)',
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked == null || _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pin to map'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
