import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/util/error_text.dart';
import '../../data/models/map_post.dart';
import '../../data/services/supabase_service.dart';
import 'map_post_providers.dart';

Future<void> showMapPostViewerSheet(BuildContext context, MapPost post) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MapPostViewerSheet(post: post),
  );
}

class _MapPostViewerSheet extends ConsumerWidget {
  final MapPost post;

  const _MapPostViewerSheet({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedUrlAsync = ref.watch(mapPostSignedUrlProvider(post.storagePath));
    final isMine = post.userId == SupabaseService.currentUser?.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: signedUrlAsync.when(
                loading: () => const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SizedBox(
                  height: 120,
                  child: Center(child: Text(friendlyError(e))),
                ),
                data: (url) => Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 160,
                    child: Center(child: Text('Could not load this photo.')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    post.posterUsername != null ? '@${post.posterUsername}' : 'Someone',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  DateFormat.yMMMd().add_jm().format(post.createdAt),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
            if (post.caption != null && post.caption!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(post.caption!),
            ],
            if (isMine) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete photo?'),
                        content: const Text('This photo will be removed for everyone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref.read(mapPostRepositoryProvider).deletePost(post.id);
                      if (post.tripId != null) {
                        ref.invalidate(tripMapPostsProvider(post.tripId!));
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete photo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
