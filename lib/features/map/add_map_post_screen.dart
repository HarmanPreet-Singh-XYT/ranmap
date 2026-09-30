import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/image_upload.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/models/trip.dart';
import '../chat/chat_providers.dart';
import '../chat/chat_share.dart';
import '../premium/paywall.dart';
import '../trip/trip_providers.dart';
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
  /// A pin can hold several photos; each is stored as its own post at the same
  /// spot, and the map stacks them under one pin.
  static const _maxPhotos = 10;

  final _captionController = TextEditingController();
  final List<XFile> _picked = [];
  bool _saving = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final room = _maxPhotos - _picked.length;
    if (room <= 0) {
      showAppToast(context, 'You can pin up to $_maxPhotos photos at a time.');
      return;
    }
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (source == ImageSource.gallery) {
        files = await picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1920,
          limit: room < 2 ? 2 : room,
        );
      } else {
        final file = await picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1920,
        );
        files = file == null ? const [] : [file];
      }
      if (files.isEmpty || !mounted) return;
      final known = {for (final f in _picked) f.path};
      setState(() {
        for (final f in files.take(room)) {
          if (known.add(f.path)) _picked.add(f);
        }
      });
      if (files.length > room && mounted) {
        showAppToast(context, 'Only the first $_maxPhotos photos were added.');
      }
    } catch (e) {
      debugPrint('pin photo: pick failed: $e');
      if (!mounted) return;
      showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _save() async {
    if (_picked.isEmpty || _saving) return;

    setState(() => _saving = true);
    final total = _picked.length;
    var saved = 0;
    final createdIds = <String>[];
    final caption = _captionController.text.trim();
    final visibility = ref.read(appSettingsProvider).photoVisibility;
    try {
      // Sequential, oldest first, so they stack in the order they were picked
      // and a mid-batch failure leaves a clean "saved N of M" state.
      for (final file in List.of(_picked)) {
        final bytes = await file.readAsBytes();
        final created = await ref
            .read(mapPostRepositoryProvider)
            .createPost(
              imageBytes: bytes,
              fileExtension: imageExtensionOf(file.name),
              lat: widget.lat,
              lng: widget.lng,
              caption: caption.isEmpty ? null : caption,
              tripId: widget.tripId,
              visibility: visibility,
            );
        saved++;
        createdIds.add(created.id);
        if (mounted) setState(() => _picked.remove(file));
      }
      ref.invalidate(tripMapPostsProvider(widget.tripId));
      await _announceInTripChat(createdIds, visibility);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('pin photo: save failed after $saved/$total: $e');
      if (saved > 0) {
        ref.invalidate(tripMapPostsProvider(widget.tripId));
        await _announceInTripChat(createdIds, visibility);
      }
      if (!mounted) return;
      // Over the free photo cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        if (saved > 0) {
          showAppToast(context, 'Pinned $saved of $total photos.');
        }
        await showPaywall(context, feature: PremiumFeature.photos);
      } else {
        showAppToast(
          context,
          saved > 0
              ? 'Pinned $saved of $total photos — ${friendlyError(e)}'
              : friendlyError(e),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// While the trip is running, drop a "Pinned image" card into its chat so the
  /// crew sees it straight away and can tap to open it. Skipped for private
  /// photos (the owner hasn't chosen to show them to the crew) and entirely
  /// best-effort: the photos are already pinned, so a chat failure is silent.
  Future<void> _announceInTripChat(List<String> postIds, String visibility) async {
    if (postIds.isEmpty || visibility == 'private') return;
    try {
      final trips = await ref.read(myTripsProvider.future);
      final trip = trips.where((t) => t.id == widget.tripId).firstOrNull;
      if (trip == null || trip.status != TripStatus.active) return;
      await sendChatShare(
        ref,
        ChatChannel.trip(widget.tripId),
        ChatShare.photos(postIds: postIds, lat: widget.lat, lng: widget.lng),
      );
    } catch (e) {
      debugPrint('pin photo: chat announce failed: $e');
    }
  }

  Widget _sourceButtons() => Row(
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
        onPressed: _saving ? null : () => _pick(ImageSource.camera),
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
        onPressed: _saving ? null : () => _pick(ImageSource.gallery),
      ),
    ],
  );

  Widget _previewGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: BrandSpace.sm,
              crossAxisSpacing: BrandSpace.sm,
            ),
            itemCount: _picked.length,
            itemBuilder: (context, i) {
              final file = _picked[i];
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(file.path), fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _saving
                          ? null
                          : () => setState(() => _picked.remove(file)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: BrandSpace.sm),
        Row(
          children: [
            Text(
              '${_picked.length} of $_maxPhotos photos',
              style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
            ),
            const Spacer(),
            if (_picked.length < _maxPhotos) _sourceButtons(),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _picked.length;
    return BrandScaffold(
      header: BrandHeader(
        title: 'Pin photos',
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
              child: _picked.isEmpty
                  ? Center(
                      child: BrandEmptyState(
                        icon: Icons.add_a_photo_outlined,
                        title: 'Add photos',
                        message:
                            'Shoot a new photo or pick several from your library to pin to this spot.',
                        action: _sourceButtons(),
                      ),
                    )
                  : _previewGrid(),
            ),
            const SizedBox(height: BrandSpace.md),
            BrandTextField(
              controller: _captionController,
              hint: count > 1
                  ? 'Caption for all photos (optional)'
                  : 'Caption (optional)',
              leadingIcon: Icons.chat_bubble_outline_rounded,
              maxLength: 200,
              maxLines: 3,
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandPrimaryButton(
              label: count > 1 ? 'Pin $count photos' : 'Pin to map',
              leadingIcon: Icons.push_pin_rounded,
              loading: _saving,
              onPressed: _picked.isEmpty || _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
