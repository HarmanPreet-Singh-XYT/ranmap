import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import '../premium/paywall.dart';
import '../premium/premium_providers.dart';
import 'social_providers.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.group});

  final Group group;

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) =>
      showAppConfirmDialog(
        context,
        title: title,
        message: body,
        confirmLabel: confirmLabel,
        destructive: true,
      );

  Future<void> _leaveGroup(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Leave group?',
      body: 'You will no longer see this group or its shared trips.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    try {
      await ref.read(groupRepositoryProvider).leaveGroup(group.id);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref, String userId, String username) async {
    final confirmed = await _confirm(
      context,
      title: 'Remove @$username?',
      body: 'They will lose access to this group and its shared trips.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await ref.read(groupRepositoryProvider).removeMember(groupId: group.id, userId: userId);
      ref.invalidate(groupMembersProvider(group.id));
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final List<Map<String, dynamic>> friendsAsync;
    try {
      friendsAsync = await ref.read(friendsProvider.future);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
      return;
    }
    final myUid = SupabaseService.currentUser?.id;
    final candidates = friendsAsync.map((row) {
      final isRequester = row['requester_id'] == myUid;
      final other = isRequester
          ? row['addressee'] as Map<String, dynamic>?
          : row['requester'] as Map<String, dynamic>?;
      return other;
    }).whereType<Map<String, dynamic>>().toList();

    if (candidates.isEmpty) {
      if (context.mounted) {
        showAppToast(context, 'Add friends first, then invite them to a group.');
      }
      return;
    }

    if (!context.mounted) return;
    final selected = await showFSheet<Map<String, dynamic>>(
      context: context,
      side: FLayout.btt,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          FTileGroup(
            children: [
              for (final profile in candidates)
                FTile(
                  prefix: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(color: NavColors.of(context).surfaceAlt, shape: BoxShape.circle),
                    child: Icon(Icons.person, color: NavColors.of(context).activeRoute, size: 20),
                  ),
                  title: Text('@${profile['username']}'),
                  onPress: () => Navigator.of(context).pop(profile),
                ),
            ],
          ),
        ],
      ),
    );

    if (selected == null) return;
    try {
      await ref
          .read(groupRepositoryProvider)
          .addMember(groupId: group.id, userId: selected['id'] as String);
      ref.invalidate(groupMembersProvider(group.id));
    } catch (e) {
      if (!context.mounted) return;
      // Over the free group-size cap (a DB trigger): offer Pro, don't error.
      if (looksPremiumRequired(e)) {
        await showPaywall(context, feature: PremiumFeature.groupSize);
      } else {
        showAppToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final myUid = SupabaseService.currentUser?.id;
    final isOwner = myUid == group.ownerId;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(group.name),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
        suffixes: [
          if (!isOwner)
            FHeaderAction(
              icon: const Icon(Icons.logout_rounded),
              onPress: () => _leaveGroup(context, ref),
            ),
        ],
      ),
      child: Stack(
        children: [
          membersAsync.when(
            data: (members) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                FTileGroup(
                  children: [
                    for (final member in members) _memberTile(context, c, ref, member, isOwner, myUid),
                  ],
                ),
              ],
            ),
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(groupMembersProvider(group.id))),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton(
              onPress: () => _addFriend(context, ref),
              prefix: const Icon(Icons.person_add),
              child: const Text('Add member'),
            ),
          ),
        ],
      ),
    );
  }

  FTile _memberTile(
    BuildContext context,
    NavColors c,
    WidgetRef ref,
    Map<String, dynamic> member,
    bool isOwner,
    String? myUid,
  ) {
    final profile = member['profiles'] as Map<String, dynamic>?;
    final userId = member['user_id'] as String?;
    final username = profile?['username'] as String? ?? 'unknown';
    final canRemove = isOwner && userId != null && userId != myUid;
    return FTile(
      prefix: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
        child: Icon(Icons.person, color: c.activeRoute, size: 20),
      ),
      title: Text('@$username'),
      suffix: canRemove
          ? FButton.icon(
              variant: .ghost,
              size: .sm,
              onPress: () => _removeMember(context, ref, userId, username),
              child: Icon(Icons.person_remove_outlined, color: c.destructive),
            )
          : Text(member['role'] as String? ?? 'member'),
    );
  }
}
