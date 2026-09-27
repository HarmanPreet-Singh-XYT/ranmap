import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../../data/models/profile.dart';
import '../../data/services/supabase_service.dart';
import 'social_providers.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Friends',
        onBack: () => Navigator.of(context).maybePop(),
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
    final friendsAsync = ref.watch(friendsProvider);

    return friendsAsync.when(
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: BrandEmptyState(
              icon: Icons.person_add_alt_1_rounded,
              title: 'No friends yet',
              message: 'Friends are the people you can invite to trips and group chats. Add them by username in the "Find people" tab.',
            ),
          );
        }

        Widget friendRow(Map<String, dynamic> row) {
          final other = _otherProfile(row);
          return BrandListRow(
            icon: Icons.person_rounded,
            title: '@${other?['username'] ?? 'unknown'}',
            showChevron: false,
            trailing: BrandFieldAction(
              icon: Icons.person_remove_outlined,
              color: BrandColors.error,
              onTap: () async {
                final confirmed = await showAppConfirmDialog(
                  context,
                  title: 'Remove friend?',
                  message:
                      'Remove @${other?['username'] ?? 'this user'} from your friends?',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
                if (!confirmed) return;
                try {
                  await ref
                      .read(friendRepositoryProvider)
                      .remove(row['id'] as String);
                  ref.invalidate(friendsProvider);
                } catch (e) {
                  if (context.mounted) {
                    showAppToast(context, friendlyError(e), error: true);
                  }
                }
              },
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
          children: [
            BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const BrandRowDivider(),
                    friendRow(row),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorRetry(error: e, onRetry: () => ref.invalidate(friendsProvider)),
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
    final incomingAsync = ref.watch(incomingRequestsProvider);
    final outgoingAsync = ref.watch(outgoingRequestsProvider);

    Widget incomingCard(Map<String, dynamic> row) {
      final requester = row['requester'] as Map<String, dynamic>?;
      return BrandCard(
        padding: const EdgeInsets.all(BrandSpace.md),
        child: Column(
          children: [
            BrandListRow(
              icon: Icons.person_rounded,
              title: '@${requester?['username'] ?? 'unknown'}',
              showChevron: false,
            ),
            const SizedBox(height: BrandSpace.xs),
            Row(
              children: [
                Expanded(
                  child: BrandPrimaryButton(
                    label: 'Accept',
                    trailingIcon: null,
                    glow: false,
                    onPressed: () async {
                      try {
                        await ref
                            .read(friendRepositoryProvider)
                            .respond(
                              friendshipId: row['id'] as String,
                              accept: true,
                            );
                        ref.invalidate(incomingRequestsProvider);
                        ref.invalidate(friendsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          showAppToast(context, friendlyError(e), error: true);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
                Expanded(
                  child: BrandSecondaryButton(
                    label: 'Decline',
                    onPressed: () async {
                      try {
                        await ref
                            .read(friendRepositoryProvider)
                            .respond(
                              friendshipId: row['id'] as String,
                              accept: false,
                            );
                        ref.invalidate(incomingRequestsProvider);
                      } catch (e) {
                        if (context.mounted) {
                          showAppToast(context, friendlyError(e), error: true);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget outgoingRow(Map<String, dynamic> row) {
      final addressee = row['addressee'] as Map<String, dynamic>?;
      return BrandListRow(
        icon: Icons.person_rounded,
        title: '@${addressee?['username'] ?? 'unknown'}',
        showChevron: false,
        trailing: BrandSecondaryButton(
          label: 'Cancel',
          expand: false,
          onPressed: () async {
            try {
              await ref
                  .read(friendRepositoryProvider)
                  .remove(row['id'] as String);
              ref.invalidate(outgoingRequestsProvider);
            } catch (e) {
              if (context.mounted) {
                showAppToast(context, friendlyError(e), error: true);
              }
            }
          },
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: BrandSpace.sm),
      children: [
        const BrandSectionHeader(
          icon: Icons.mark_email_unread_rounded,
          title: 'Incoming',
        ),
        const SizedBox(height: BrandSpace.sm),
        incomingAsync.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const BrandEmptyState(
                icon: Icons.inbox_rounded,
                title: 'No pending requests',
                message: 'When someone asks to be your friend, their request lands here to accept or decline.',
              );
            }
            return Column(
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const SizedBox(height: BrandSpace.sm),
                  incomingCard(row),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(incomingRequestsProvider),
          ),
        ),
        const SizedBox(height: BrandSpace.lg),
        const BrandSectionHeader(icon: Icons.outbox_rounded, title: 'Sent'),
        const SizedBox(height: BrandSpace.sm),
        outgoingAsync.when(
          data: (rows) {
            if (rows.isEmpty) {
              return const BrandEmptyState(
                icon: Icons.outbox_rounded,
                title: 'No outgoing requests',
                message:
                    'Friend requests you send stay here until they accept.',
              );
            }
            return BrandCard(
              padding: const EdgeInsets.symmetric(
                horizontal: BrandSpace.md,
                vertical: BrandSpace.xs,
              ),
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const BrandRowDivider(),
                    outgoingRow(row),
                  ],
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(
            error: e,
            onRetry: () => ref.invalidate(outgoingRequestsProvider),
          ),
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
  Timer? _debounce;
  String _query = '';
  final Set<String> _requested = {};
  final Set<String> _submitting = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounce the search so each keystroke doesn't fire its own request (the
  /// query is the provider's family key, so every character would otherwise
  /// create a new provider instance and round-trip).
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && value != _query) setState(() => _query = value);
    });
  }

  Future<void> _add(Profile profile) async {
    if (_submitting.contains(profile.id)) return;
    setState(() => _submitting.add(profile.id));
    try {
      await ref.read(friendRepositoryProvider).sendRequest(profile.id);
      if (!mounted) return;
      setState(() => _requested.add(profile.id));
      ref.invalidate(outgoingRequestsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting.remove(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchProvider(_query));

    Widget resultRow(Profile profile) {
      final alreadyRequested = _requested.contains(profile.id);
      final busy = _submitting.contains(profile.id);
      return BrandListRow(
        icon: Icons.person_rounded,
        title: '@${profile.username}',
        showChevron: false,
        trailing: alreadyRequested
            ? const BrandPill(label: 'Requested')
            : BrandPrimaryButton(
                label: 'Add',
                expand: false,
                trailingIcon: null,
                glow: false,
                loading: busy,
                onPressed: busy ? null : () => _add(profile),
              ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.md),
          child: BrandTextField(
            controller: _controller,
            hint: 'Search by username',
            leadingIcon: Icons.search_rounded,
            onChanged: _onQueryChanged,
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            data: (results) {
              if (_query.trim().length < 2) {
                return const Center(
                  child: BrandEmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'Find your crew',
                    message: 'Type at least 2 characters to search for someone by username, then send a friend request.',
                  ),
                );
              }
              if (results.isEmpty) {
                return Center(
                  child: BrandEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message:
                        'No one matches "$_query". Check the spelling or try a different username.',
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: BrandSpace.lg),
                children: [
                  BrandCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BrandSpace.md,
                      vertical: BrandSpace.xs,
                    ),
                    child: Column(
                      children: [
                        for (final (i, profile) in results.indexed) ...[
                          if (i > 0) const BrandRowDivider(),
                          resultRow(profile),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              error: e,
              onRetry: () => ref.invalidate(usernameSearchProvider(_query)),
            ),
          ),
        ),
      ],
    );
  }
}
