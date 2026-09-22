import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/error_text.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import '../../data/services/supabase_service.dart';
import 'social_providers.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.group});

  final Group group;

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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));

    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: membersAsync.when(
        data: (members) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final member = members[i];
            final profile = member['profiles'] as Map<String, dynamic>?;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('@${profile?['username'] ?? 'unknown'}'),
              trailing: Text(member['role'] as String? ?? 'member'),
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
