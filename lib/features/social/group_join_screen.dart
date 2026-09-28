import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../data/models/group.dart';
import 'group_detail_screen.dart';
import 'invite_providers.dart';
import 'social_providers.dart';

/// Lands someone who opened a group invite link (`/join/<code>`).
///
/// Signed in, it previews the group and lets them join (or request to join).
/// Signed out, it remembers the code and points at sign-up, so the flow
/// survives the auth round trip — [HomeShell] re-opens it once they're in.
class GroupJoinScreen extends ConsumerStatefulWidget {
  const GroupJoinScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends ConsumerState<GroupJoinScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authStateProvider).valueOrNull?.session;
    if (session != null) {
      unawaited(ref.read(pendingGroupJoinProvider.notifier).clear());
    }
  }

  void _dismiss() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      context.go('/');
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final (result, groupId) = await ref
          .read(groupRepositoryProvider)
          .joinGroup(widget.code);
      ref.invalidate(myGroupsProvider);
      if (!mounted) return;
      switch (result) {
        case JoinGroupResult.joined:
        case JoinGroupResult.alreadyMember:
          if (groupId == null) {
            _dismiss();
            return;
          }
          final Group group = await ref
              .read(groupRepositoryProvider)
              .fetchGroup(groupId);
          if (!mounted) return;
          // Replace the join screen so Back returns to where they came from,
          // not to a now-redundant invite.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
          );
        case JoinGroupResult.pending:
        case JoinGroupResult.alreadyRequested:
          showAppToast(context, 'Request sent — an admin will approve it.');
          _dismiss();
        case JoinGroupResult.notFound:
          showAppToast(context, 'That invite code is not valid.', error: true);
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider).valueOrNull?.session != null;
    // A signed-out recipient can't preview a group (the lookup is a member
    // RPC), so prompt for auth instead. The code was already persisted by the
    // deep-link handler, and [HomeShell] re-opens this screen once they're in.
    if (!signedIn) {
      return _Shell(onBack: _dismiss, child: const _SignedOut());
    }

    final previewAsync = ref.watch(groupInvitePreviewProvider(widget.code));
    return _Shell(
      onBack: _dismiss,
      child: previewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.link_off_rounded,
          title: 'Could not open this invite',
          message: friendlyError(e),
          onBack: _dismiss,
        ),
        data: (preview) {
          if (preview == null) {
            return _Message(
              icon: Icons.link_off_rounded,
              title: 'Invite not found',
              message: 'This invite link may have been reset or expired.',
              onBack: _dismiss,
            );
          }
          return _Preview(
            preview: preview,
            busy: _busy,
            onJoin: _busy ? null : _join,
            onBack: _dismiss,
          );
        },
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.onBack});

  final Widget child;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => BrandScaffold(
    header: BrandHeader(title: 'Group invite', onBack: onBack),
    child: child,
  );
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.preview,
    required this.busy,
    required this.onJoin,
    required this.onBack,
  });

  final GroupInvitePreview preview;
  final bool busy;
  final VoidCallback? onJoin;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final isMember = preview.membership == 'member';
    final isPending = preview.membership == 'pending';
    final label = isPending
        ? 'Request pending'
        : preview.requiresApproval
        ? 'Request to join'
        : 'Join group';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: BrandSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarView(
              seed: preview.avatarId,
              size: 96,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(height: BrandSpace.md),
            Text(
              preview.name,
              textAlign: TextAlign.center,
              style: BrandText.headlineMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            const SizedBox(height: BrandSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
              child: Text(
                preview.description?.isNotEmpty == true
                    ? preview.description!
                    : 'You have been invited to join this group.',
                textAlign: TextAlign.center,
                style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              ),
            ),
            const SizedBox(height: BrandSpace.sm),
            BrandPill(
              icon: Icons.groups_rounded,
              label:
                  '${preview.memberCount} ${preview.memberCount == 1 ? 'member' : 'members'}',
            ),
            const SizedBox(height: BrandSpace.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
              child: Column(
                children: [
                  if (isPending)
                    BrandSecondaryButton(label: label, onPressed: null)
                  else
                    BrandPrimaryButton(
                      label: label,
                      leadingIcon: isMember
                          ? Icons.arrow_forward_rounded
                          : Icons.group_add_rounded,
                      loading: busy,
                      onPressed: onJoin,
                    ),
                  const SizedBox(height: BrandSpace.gutterSm),
                  BrandSecondaryButton(
                    label: 'Not now',
                    onPressed: busy ? null : onBack,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: BrandSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarView(
              seed: kDefaultAvatarSeed,
              size: 96,
              background: BrandColors.surfaceContainerLow,
              accentColor: BrandColors.primary,
            ),
            const SizedBox(height: BrandSpace.md),
            Text(
              'You have been invited',
              style: BrandText.headlineMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            const SizedBox(height: BrandSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
              child: Text(
                'Create an account or sign in to join this group. We will take '
                'you straight back here.',
                textAlign: TextAlign.center,
                style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              ),
            ),
            const SizedBox(height: BrandSpace.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
              child: Column(
                children: [
                  BrandPrimaryButton(
                    label: 'Create an account',
                    onPressed: () => context.push('/sign-up'),
                  ),
                  const SizedBox(height: BrandSpace.gutterSm),
                  BrandSecondaryButton(
                    label: 'I already have an account',
                    onPressed: () => context.push('/sign-in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.onBack,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BrandEmptyState(
        icon: icon,
        title: title,
        message: message,
        action: BrandSecondaryButton(
          label: 'Back to Ranmap',
          expand: false,
          onPressed: onBack,
        ),
      ),
    );
  }
}
