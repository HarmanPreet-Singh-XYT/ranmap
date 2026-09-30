import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/save_image.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import '../../data/models/group.dart';
import '../../data/models/map_post.dart';
import '../../data/services/supabase_service.dart';
import '../chat/chat_share.dart';
import '../social/moderation_actions.dart';
import '../social/social_providers.dart';
import 'map_post_providers.dart';

/// Opens [post] in the viewer. Pass [stack] — the photos pinned at the same
/// spot (or any related set, [post] included) — to let the user swipe between
/// them.
Future<void> showMapPostViewerSheet(
  BuildContext context,
  MapPost post, {
  List<MapPost>? stack,
}) {
  final posts = stack == null || stack.isEmpty ? [post] : stack;
  final index = posts.indexWhere((p) => p.id == post.id);
  return showFSheet(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (_) =>
        _MapPostViewerSheet(posts: posts, initialIndex: index < 0 ? 0 : index),
  );
}

class _MapPostViewerSheet extends ConsumerStatefulWidget {
  final List<MapPost> posts;
  final int initialIndex;

  const _MapPostViewerSheet({required this.posts, required this.initialIndex});

  @override
  ConsumerState<_MapPostViewerSheet> createState() =>
      _MapPostViewerSheetState();
}

class _MapPostViewerSheetState extends ConsumerState<_MapPostViewerSheet> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  MapPost get post => widget.posts[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Shares this photo with one of the user's groups, which makes it readable
  /// to every member (see `can_view_map_post` / `map_post_shares`).
  Future<void> _shareToGroup(BuildContext context, WidgetRef ref) async {
    final groups = ref.read(myGroupsProvider).valueOrNull ?? const <Group>[];
    if (groups.isEmpty) {
      showAppToast(
        context,
        'Create a group first, then share with it.',
        error: true,
      );
      return;
    }
    final selected = await showFSheet<String>(
      context: context,
      side: FLayout.btt,
      builder: (context) => BrandSheetSurface(
        child: BrandCard(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandSpace.md,
            vertical: BrandSpace.xs,
          ),
          child: Column(
            children: [
              for (final (i, group) in groups.indexed) ...[
                if (i > 0) const BrandRowDivider(),
                BrandListRow(
                  icon: Icons.groups_rounded,
                  iconColor: BrandColors.primary,
                  title: group.name,
                  showChevron: false,
                  onTap: () => Navigator.of(context).pop(group.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await ref
          .read(mapPostRepositoryProvider)
          .shareWithGroup(postId: post.id, groupId: selected);
      if (context.mounted) showAppToast(context, 'Shared with the group.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  /// Shares this photo with one friend so they can open it from "Shared with
  /// me" even if they're not on the trip or in one of the groups.
  Future<void> _shareToFriend(BuildContext context, WidgetRef ref) async {
    final List<Map<String, dynamic>> friendRows;
    try {
      friendRows = await ref.read(friendsProvider.future);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final myUid = SupabaseService.currentUser?.id;
    final friends = friendRows
        .map(
          (row) =>
              (row['requester_id'] == myUid
                      ? row['addressee']
                      : row['requester'])
                  as Map<String, dynamic>?,
        )
        .whereType<Map<String, dynamic>>()
        .toList();
    if (!context.mounted) return;
    if (friends.isEmpty) {
      showAppToast(
        context,
        'No friends yet — add some from Profile > Friends.',
        error: true,
      );
      return;
    }
    final selected = await showFSheet<Map<String, dynamic>>(
      context: context,
      side: FLayout.btt,
      builder: (sheetContext) => BrandSheetSurface(
        child: SingleChildScrollView(
          child: BrandCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BrandSpace.md,
              vertical: BrandSpace.xs,
            ),
            child: Column(
              children: [
                for (final (i, friend) in friends.indexed) ...[
                  if (i > 0) const BrandRowDivider(),
                  BrandListRow(
                    icon: Icons.person_rounded,
                    iconColor: BrandColors.primary,
                    title:
                        (friend['display_name'] as String?)?.isNotEmpty == true
                        ? friend['display_name'] as String
                        : '@${friend['username']}',
                    subtitle: '@${friend['username']}',
                    showChevron: false,
                    onTap: () => Navigator.of(sheetContext).pop(friend),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final friendId = selected?['id'] as String?;
    if (friendId == null || !context.mounted) return;
    try {
      await ref
          .read(mapPostRepositoryProvider)
          .shareWithUser(postId: post.id, userId: friendId);
      if (context.mounted) {
        showAppToast(context, 'Shared with @${selected!['username']}.');
      }
    } catch (e) {
      if (!context.mounted) return;
      // The (post, friend) pair is unique: sharing twice is not a failure.
      final alreadyShared = e is PostgrestException && e.code == '23505';
      showAppToast(
        context,
        alreadyShared
            ? 'Already shared with @${selected!['username']}.'
            : friendlyError(e),
        error: !alreadyShared,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedUrlAsync = ref.watch(
      mapPostSignedUrlProvider(post.storagePath),
    );
    final isMine = post.userId == SupabaseService.currentUser?.id;

    return BrandSheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.posts.length > 1) ...[
            SizedBox(
              height: 300,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: widget.posts.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _PostImage(post: widget.posts[i]),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.posts.length}',
                        style: BrandText.labelSm.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BrandSpace.sm),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.posts.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: i == _index ? 16 : 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? BrandColors.primary
                            : BrandColors.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ] else
            _PostImage(post: post, fixedHeight: false),
          const SizedBox(height: BrandSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  post.posterUsername != null
                      ? '@${post.posterUsername}'
                      : 'Someone',
                  style: BrandText.titleSm.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
              ),
              Text(
                DateFormat.yMMMd().add_jm().format(post.createdAt.toLocal()),
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
              IconButton(
                tooltip: 'Save to Photos',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.download_rounded,
                  color: BrandColors.textHeadline,
                ),
                onPressed: signedUrlAsync.valueOrNull == null
                    ? null
                    : () => saveImageUrlToGallery(
                        context,
                        signedUrlAsync.requireValue,
                        name: 'ranmap_${post.id}',
                      ),
              ),
            ],
          ),
          if (post.caption != null && post.caption!.isNotEmpty) ...[
            const SizedBox(height: BrandSpace.sm),
            Text(
              post.caption!,
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
          ],
          if (isMine) ...[
            const SizedBox(height: BrandSpace.md),
            BrandSecondaryButton(
              label: 'Send in chat',
              leading: Icon(
                Icons.send_rounded,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () => showShareToSheet(
                context,
                ref,
                title: 'Send photo',
                share: ChatShare.photos(
                  postIds: [post.id],
                  lat: post.lat,
                  lng: post.lng,
                ),
              ),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandSecondaryButton(
              label: 'Share to a group',
              leading: Icon(
                Icons.groups_rounded,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () => _shareToGroup(context, ref),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandSecondaryButton(
              label: 'Share with a friend',
              leading: Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () => _shareToFriend(context, ref),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandPressable(
              onTap: () async {
                final confirmed = await showAppConfirmDialog(
                  context,
                  title: 'Delete photo?',
                  message: 'This photo will be removed for everyone.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!confirmed) return;
                try {
                  await ref.read(mapPostRepositoryProvider).deletePost(post.id);
                  if (post.tripId != null) {
                    ref.invalidate(tripMapPostsProvider(post.tripId!));
                  }
                } catch (e) {
                  if (context.mounted) {
                    showAppToast(context, friendlyError(e), error: true);
                  }
                  return;
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: BrandColors.errorContainer,
                  borderRadius: BrandRadii.pill,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: BrandColors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete photo',
                      style: BrandText.weight(
                        BrandText.labelLg,
                        700,
                      ).copyWith(color: BrandColors.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: BrandSpace.md),
            BrandSecondaryButton(
              label: 'Report photo',
              leading: Icon(
                Icons.flag_outlined,
                size: 18,
                color: BrandColors.textHeadlineAlt,
              ),
              onPressed: () => showReportSheet(
                context,
                ref,
                targetType: 'post',
                targetId: post.id,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One post's photo, loaded through its signed URL.
class _PostImage extends ConsumerWidget {
  const _PostImage({required this.post, this.fixedHeight = true});

  final MapPost post;

  /// Fill the parent's height (inside a pager) rather than sizing to the image.
  final bool fixedHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedUrlAsync = ref.watch(
      mapPostSignedUrlProvider(post.storagePath),
    );
    return ClipRRect(
      borderRadius: BrandRadii.cardRadius,
      child: signedUrlAsync.when(
        loading: () => SizedBox(
          height: 240,
          child: Center(
            child: CircularProgressIndicator(
              color: BrandColors.primaryContainer,
            ),
          ),
        ),
        error: (e, _) => SizedBox(
          height: 120,
          child: Center(
            child: Text(
              friendlyError(e),
              style: BrandText.bodyMd.copyWith(color: BrandColors.error),
            ),
          ),
        ),
        data: (url) => CachedNetworkImage(
          imageUrl: url,
          cacheKey: post.storagePath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: fixedHeight ? double.infinity : null,
          placeholder: (_, _) => SizedBox(
            height: 240,
            child: Center(
              child: CircularProgressIndicator(
                color: BrandColors.primaryContainer,
              ),
            ),
          ),
          errorWidget: (_, _, _) => SizedBox(
            height: 160,
            child: Center(
              child: Text(
                'Could not load this photo.',
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
