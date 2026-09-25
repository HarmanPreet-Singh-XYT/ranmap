import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/group.dart';
import 'group_detail_screen.dart';
import 'social_providers.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await showAppTextDialog(
      context,
      title: 'New group',
      label: 'Group name',
      hint: 'Weekend crew',
      maxLength: kNameMaxLength,
    );
    if (name == null) return;
    final validationError = nameError(name, label: 'Group name');
    if (validationError != null) {
      if (context.mounted) showAppToast(context, validationError, error: true);
      return;
    }
    try {
      await ref.read(groupRepositoryProvider).createGroup(name);
      ref.invalidate(myGroupsProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final groupsAsync = ref.watch(myGroupsProvider);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Groups'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: Stack(
        children: [
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No groups yet. Create one to start planning trips together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.mutedForeground),
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  FTileGroup(
                    children: [
                      for (final Group group in groups)
                        FTile(
                          prefix: Container(
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                            child: Icon(Icons.groups_rounded, color: c.activeRoute, size: 20),
                          ),
                          title: Text(
                            group.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          suffix: Icon(Icons.chevron_right_rounded, color: c.mutedForeground),
                          onPress: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myGroupsProvider)),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton(
              onPress: () => _createGroup(context, ref),
              prefix: const Icon(Icons.add),
              child: const Text('New group'),
            ),
          ),
        ],
      ),
    );
  }
}
