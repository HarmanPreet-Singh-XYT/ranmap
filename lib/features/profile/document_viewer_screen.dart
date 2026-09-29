import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/save_image.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/user_document.dart';
import 'profile_extras_providers.dart';

/// Shows a wallet document in place: downloaded with the user's session and
/// rendered with pinch-to-zoom. Files the app can't decode fall back to
/// opening externally.
class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({super.key, required this.document});

  final UserDocument document;

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  late Future<Uint8List> _bytes = _load();
  Uint8List? _loaded;

  Future<Uint8List> _load() async {
    final bytes = await ref
        .read(documentRepositoryProvider)
        .download(widget.document.storagePath);
    if (mounted) setState(() => _loaded = bytes);
    return bytes;
  }

  Future<void> _openExternally() async {
    final url = await ref
        .read(documentRepositoryProvider)
        .signedUrl(widget.document.storagePath);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: widget.document.name,
        onBack: () => Navigator.of(context).maybePop(),
        actionIcon: Icons.download_rounded,
        actionTooltip: 'Save to Photos',
        onAction: _loaded == null
            ? null
            : () => saveImageToGallery(
                context,
                _loaded!,
                name: widget.document.name,
              ),
      ),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetry(
              error: snapshot.error!,
              onRetry: () => setState(() => _bytes = _load()),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
            child: ClipRRect(
              borderRadius: BrandRadii.podRadius,
              child: ColoredBox(
                color: BrandColors.surfaceContainerLow,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => _Unsupported(
                      onOpen: () async {
                        try {
                          await _openExternally();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(content: Text(friendlyError(e))),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BrandSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: BrandColors.textMuted,
            ),
            const SizedBox(height: BrandSpace.sm),
            Text(
              "This file can't be previewed in the app.",
              textAlign: TextAlign.center,
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
            const SizedBox(height: BrandSpace.md),
            BrandSecondaryButton(
              label: 'Open with another app',
              expand: false,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
