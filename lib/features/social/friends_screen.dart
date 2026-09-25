import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/profile.dart';
import '../../data/services/supabase_service.dart';
import 'social_providers.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Friends'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: FTabs(
        expands: true,
        children: const [
          FTabEntry(label: Text('Friends'), child: _FriendsTab()),
          FTabEntry(label: Text('Requests'), child: _RequestsTab()),
          FTabEntry(label: Text('Find people'), child: _FindPeopleTab()),
        ],
      ),
    );
  }
}

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final friendsAsync = ref.watch(friendsProvider);

    return friendsAsync.when(
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No friends yet. Find people in the next tab.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground),
              ),
            ),
          );
        }

        Widget avatar() => Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
              child: Icon(Icons.person, color: c.activeRoute, size: 20),
            );

        FTile friendTile(Map<String, dynamic> row) {
          final other = _otherProfile(row);
          return FTile(
            prefix: avatar(),
            title: Text('@${other?['username'] ?? 'unknown'}'),
            suffix: FButton.icon(
              variant: .ghost,
              size: .sm,
              onPress: () async {
                final confirmed = await showAppConfirmDialog(
                  context,
                  title: 'Remove friend?',
                  message: 'Remove @${other?['username'] ?? 'this user'} from your friends?',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
                if (!confirmed) return;
                try {
                  await ref.read(friendRepositoryProvider).remove(row['id'] as String);
                  ref.invalidate(friendsProvider);
                } catch (e) {
                  if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                }
              },
              child: Icon(Icons.person_remove_outlined, color: c.destructive),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FTileGroup(children: [for (final row in rows) friendTile(row)]),
          ],
        );
      },
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(friendsProvider)),
    );
  }

  Map<String, dynamic>? _otherProfile(Map<String, dynamic> row) {
    final myUid = SupabaseService.currentUser?.id;
    final isRequester = row['requester_id'] == myUid;
    return isRequester
        ? row['addressee'] as Map<String, dynamic>?
        : row['requester'] as Map<String, dynamic>?;
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = NavColors.of(context);
    final incomingAsync = ref.watch(incomingRequestsProvider);
    final outgoingAsync = ref.watch(outgoingRequestsProvider);

    Widget avatar() => Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(Icons.person, color: c.activeRoute, size: 20),
        );

    FTile incomingTile(Map<String, dynamic> row) {
      final requester = row['requester'] as Map<String, dynamic>?;
      return FTile(
        prefix: avatar(),
        title: Text('@${requester?['username'] ?? 'unknown'}'),
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FButton(
              size: .sm,
              onPress: () async {
                try {
                  await ref
                      .read(friendRepositoryProvider)
                      .respond(friendshipId: row['id'] as String, accept: true);
                  ref.invalidate(incomingRequestsProvider);
                  ref.invalidate(friendsProvider);
                } catch (e) {
                  if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                }
              },
              child: const Text('Accept'),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: .outline,
              size: .sm,
              onPress: () async {
                try {
                  await ref
                      .read(friendRepositoryProvider)
                      .respond(friendshipId: row['id'] as String, accept: false);
                  ref.invalidate(incomingRequestsProvider);
                } catch (e) {
                  if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                }
              },
              child: const Text('Decline'),
            ),
          ],
        ),
      );
    }

    FTile outgoingTile(Map<String, dynamic> row) {
      final addressee = row['addressee'] as Map<String, dynamic>?;
      return FTile(
        prefix: avatar(),
        title: Text('@${addressee?['username'] ?? 'unknown'}'),
        suffix: FButton(
          variant: .ghost,
          size: .sm,
          onPress: () async {
            try {
              await ref.read(friendRepositoryProvider).remove(row['id'] as String);
              ref.invalidate(outgoingRequestsProvider);
            } catch (e) {
              if (context.mounted) showAppToast(context, friendlyError(e), error: true);
            }
          },
          child: const Text('Cancel'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Incoming', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
        const SizedBox(height: 10),
        incomingAsync.when(
          data: (rows) {
            if (rows.isEmpty) return Text('No pending requests.', style: TextStyle(color: c.mutedForeground));
            return FTileGroup(children: [for (final row in rows) incomingTile(row)]);
          },
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(incomingRequestsProvider)),
        ),
        const SizedBox(height: 24),
        Text('Sent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground)),
        const SizedBox(height: 10),
        outgoingAsync.when(
          data: (rows) {
            if (rows.isEmpty) return Text('No outgoing requests.', style: TextStyle(color: c.mutedForeground));
            return FTileGroup(children: [for (final row in rows) outgoingTile(row)]);
          },
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(outgoingRequestsProvider)),
        ),
      ],
    );
  }
}

class _FindPeopleTab extends ConsumerStatefulWidget {
  const _FindPeopleTab();

  @override
  ConsumerState<_FindPeopleTab> createState() => _FindPeopleTabState();
}

class _FindPeopleTabState extends ConsumerState<_FindPeopleTab> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<String> _requested = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final resultsAsync = ref.watch(usernameSearchProvider(_query));

    FTile resultTile(Profile profile) {
      final alreadyRequested = _requested.contains(profile.id);
      return FTile(
        prefix: Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(Icons.person, color: c.activeRoute, size: 20),
        ),
        title: Text('@${profile.username}'),
        suffix: alreadyRequested
            ? Text('Requested', style: TextStyle(color: c.mutedForeground))
            : FButton(
                size: .sm,
                onPress: () async {
                  try {
                    await ref.read(friendRepositoryProvider).sendRequest(profile.id);
                    setState(() => _requested.add(profile.id));
                    ref.invalidate(outgoingRequestsProvider);
                  } catch (e) {
                    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
                  }
                },
                child: const Text('Add'),
              ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FTextField(
            control: FTextFieldControl.managed(
              controller: _controller,
              onChange: (value) => setState(() => _query = value.text),
            ),
            label: const Text('Search by username'),
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            data: (results) {
              if (_query.trim().length < 2) {
                return Center(
                  child: Text(
                    'Type at least 2 characters to search.',
                    style: TextStyle(color: c.mutedForeground),
                  ),
                );
              }
              if (results.isEmpty) {
                return Center(child: Text('No matches.', style: TextStyle(color: c.mutedForeground)));
              }
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FTileGroup(children: [for (final profile in results) resultTile(profile)]),
                ],
              );
            },
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) =>
                ErrorRetry(error: e, onRetry: () => ref.invalidate(usernameSearchProvider(_query))),
          ),
        ),
      ],
    );
  }
}
