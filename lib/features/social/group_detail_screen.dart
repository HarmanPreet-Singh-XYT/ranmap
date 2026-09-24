import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/error_text.dart';
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
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _addFriend(BuildContext context, WidgetRef ref) async {
    final List<Map<String, dynamic>> friendsAsync;
    try {
      friendsAsync = await ref.read(friendsProvider.future);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add friends first, then invite them to a group.')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: candidates.map((profile) {
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@${profile['username']}'),
              onTap: () => Navigator.of(context).pop(profile),
            );
          }).toList(),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final myUid = SupabaseService.currentUser?.id;
    final isOwner = myUid == group.ownerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          if (!isOwner)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Leave group',
              onPressed: () => _leaveGroup(context, ref),
            ),
        ],
      ),
      body: membersAsync.when(
        data: (members) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final member = members[i];
            final profile = member['profiles'] as Map<String, dynamic>?;
            final userId = member['user_id'] as String?;
            final username = profile?['username'] as String? ?? 'unknown';
            final canRemove = isOwner && userId != null && userId != myUid;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@$username'),
              trailing: canRemove
                  ? IconButton(
                      icon: const Icon(Icons.person_remove_outlined),
                      tooltip: 'Remove @$username',
                      onPressed: () => _removeMember(context, ref, userId, username),
                    )
                  : Text(member['role'] as String? ?? 'member'),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(groupMembersProvider(group.id))),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFriend(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Add member'),
      ),
    );
  }
}
