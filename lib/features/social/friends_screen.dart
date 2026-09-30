import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_action_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_list_row.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import '../chat/direct_messages_screen.dart';
import '../../data/models/profile.dart';
import '../../data/services/supabase_service.dart';
import 'invite_share.dart';
import 'social_providers.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Friends',
        onBack: () => Navigator.of(context).maybePop(),
        actionIcon: Icons.ios_share_rounded,
        actionTooltip: 'Share your invite link',
        onAction: () => shareMyInviteLink(context, ref),
      ),
      child: FTabs(
        expands: true,
        children: const [
          FTabEntry(label: Text('Friends'), child: _FriendsTab()),
          FTabEntry(label: Text('Requests'), child: _RequestsTab()),
          FTabEntry(label: Text('Find'), child: _FindPeopleTab()),
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
          return Center(
            child: SingleChildScrollView(
              child: BrandEmptyState(
                imageAsset: 'assets/images/scenic/friends_crew_scenic.jpg',
                icon: Icons.person_add_alt_1_rounded,
                title: 'Build your road trip crew',
                message: 'Connect with friends to invite them to live convoys, share routes, and sync pitstops. Share your invite link, or search by username in the Find People tab.',
                action: BrandPrimaryButton(
                  label: 'Invite friends',
                  leadingIcon: Icons.ios_share_rounded,
                  expand: false,
                  onPressed: () => shareMyInviteLink(context, ref),
                ),
              ),
            ),
          );
        }

        Widget friendRow(Map<String, dynamic> row) {
          final other = _otherProfile(row);
          Future<void> removeFriend() async {
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
          }

          return BrandListRow(
            icon: Icons.person_rounded,
            title: '@${other?['username'] ?? 'unknown'}',
            subtitle: 'Tap to message · hold for options',
            showChevron: false,
            trailing: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: BrandColors.textMuted,
            ),
            onTap: other?['id'] == null
                ? null
                : () => openDirectChat(
                    context,
                    ref,
                    otherUserId: other!['id'] as String,
                    title:
                        (other['display_name'] as String?)?.isNotEmpty == true
                        ? other['display_name'] as String
                        : '@${other['username']}',
                  ),
            onLongPress: () => showAppActionSheet(
              context,
              title: '@${other?['username'] ?? 'friend'}',
              actions: [
                if (other?['id'] != null)
                  AppSheetAction(
                    label: 'Message',
                    icon: Icons.chat_bubble_outline_rounded,
                    onSelected: () => openDirectChat(
                      context,
                      ref,
                      otherUserId: other!['id'] as String,
                      title:
                          (other['display_name'] as String?)?.isNotEmpty == true
                          ? other['display_name'] as String
                          : '@${other['username']}',
                    ),
                  ),
                AppSheetAction(
                  label: 'Remove friend',
                  icon: Icons.person_remove_outlined,
                  destructive: true,
                  onSelected: removeFriend,
                ),
              ],
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

class _RequestsTab extends ConsumerStatefulWidget {
  const _RequestsTab();

  @override
  ConsumerState<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<_RequestsTab> {
  /// Friendship ids with an in-flight accept/decline/cancel, so a double tap
  /// can't submit the same action twice.
  final Set<String> _busy = {};

  Future<void> _respond(String friendshipId, bool accept) async {
    if (_busy.contains(friendshipId)) return;
    setState(() => _busy.add(friendshipId));
    try {
      await ref
          .read(friendRepositoryProvider)
          .respond(friendshipId: friendshipId, accept: accept);
      ref.invalidate(incomingRequestsProvider);
      ref.invalidate(friendsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(friendshipId));
    }
  }

  Future<void> _cancel(String friendshipId) async {
    if (_busy.contains(friendshipId)) return;
    setState(() => _busy.add(friendshipId));
    try {
      await ref.read(friendRepositoryProvider).remove(friendshipId);
      ref.invalidate(outgoingRequestsProvider);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(friendshipId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final incomingAsync = ref.watch(incomingRequestsProvider);
    final outgoingAsync = ref.watch(outgoingRequestsProvider);

    Widget incomingCard(Map<String, dynamic> row) {
      final id = row['id'] as String;
      final busy = _busy.contains(id);
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
                    loading: busy,
                    onPressed: busy ? null : () => _respond(id, true),
                  ),
                ),
                const SizedBox(width: BrandSpace.sm),
                Expanded(
                  child: BrandSecondaryButton(
                    label: 'Decline',
                    onPressed: busy ? null : () => _respond(id, false),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget outgoingRow(Map<String, dynamic> row) {
      final id = row['id'] as String;
      final busy = _busy.contains(id);
      final addressee = row['addressee'] as Map<String, dynamic>?;
      return BrandListRow(
        icon: Icons.person_rounded,
        title: '@${addressee?['username'] ?? 'unknown'}',
        showChevron: false,
        trailing: BrandSecondaryButton(
          label: 'Cancel',
          expand: false,
          onPressed: busy ? null : () => _cancel(id),
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
