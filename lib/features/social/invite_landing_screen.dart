import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import 'invite_providers.dart';
import 'social_providers.dart';

/// Lands someone who opened an invite link (`/invite/<username>`). A signed-in
/// user can add the inviter as a friend on the spot; a signed-out one is
/// pointed at sign-up, and [HomeShell] offers the same action once they're in.
class InviteLandingScreen extends ConsumerStatefulWidget {
  const InviteLandingScreen({super.key, required this.username});

  final String username;

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A signed-in user handles the invite right here; a signed-out one keeps it
    // so it can be offered again after sign-up / onboarding.
    final session = ref.read(authStateProvider).valueOrNull?.session;
    if (session != null) {
      unawaited(ref.read(pendingInviteProvider.notifier).clear());
    }
  }

  /// Leaves the invite screen. It may have been opened by a deep link with no
  /// route beneath it (`go` replaces the stack), so fall back to home rather
  /// than stranding the user on a screen `maybePop` can't dismiss.
  void _dismiss() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      context.go('/');
    }
  }

  Future<void> _addFriend() async {
    setState(() => _busy = true);
    try {
      final sent = await ref
          .read(friendRepositoryProvider)
          .sendRequestByUsername(widget.username);
      if (!mounted) return;
      showAppToast(
        context,
        sent
            ? 'Friend request sent to @${widget.username}.'
            : 'No user found with username "${widget.username}".',
        error: !sent,
      );
      if (sent) _dismiss();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider).valueOrNull?.session != null;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final isSelf = me?.username == widget.username;
    final seed =
        ref.watch(profileByUsernameProvider(widget.username)).valueOrNull?.avatarId ??
        kDefaultAvatarSeed;

    return BrandScaffold(
      header: BrandHeader(title: 'Invite', onBack: _dismiss),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: BrandSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarView(
                seed: seed,
                size: 96,
                background: BrandColors.surfaceContainerLow,
                accentColor: BrandColors.primary,
              ),
              const SizedBox(height: BrandSpace.md),
              Text(
                '@${widget.username}',
                style: BrandText.headlineMd.copyWith(
                  color: BrandColors.textHeadline,
                ),
              ),
              const SizedBox(height: BrandSpace.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
                child: Text(
                  isSelf
                      ? "That's your own invite link."
                      : 'invited you to ride together on Ranmap.',
                  textAlign: TextAlign.center,
                  style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
                ),
              ),
              const SizedBox(height: BrandSpace.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BrandSpace.lg),
                child: _actions(signedIn: signedIn, isSelf: isSelf),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions({required bool signedIn, required bool isSelf}) {
    if (signedIn) {
      if (isSelf) {
        return BrandPrimaryButton(
          label: 'Back to Ranmap',
          onPressed: _dismiss,
        );
      }
      return Column(
        children: [
          BrandPrimaryButton(
            label: 'Add @${widget.username}',
            leadingIcon: Icons.person_add_alt_1_rounded,
            loading: _busy,
            onPressed: _busy ? null : _addFriend,
          ),
          const SizedBox(height: BrandSpace.gutterSm),
          BrandSecondaryButton(
            label: 'Not now',
            onPressed: _busy ? null : _dismiss,
          ),
        ],
      );
    }
    return Column(
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
    );
  }
}

/// The post-auth prompt offering a pending invite once the user is back home
/// (e.g. after signing up from an invite link). Returns true to send the
/// request, false/null to decline.
Future<bool?> showPendingInvitePrompt(
  BuildContext context, {
  required String username,
}) {
  return showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    builder: (_) => _PendingInviteSheet(username: username),
  );
}

class _PendingInviteSheet extends ConsumerWidget {
  const _PendingInviteSheet({required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the inviter's real avatar, matching the invite screen the user may
    // already have seen.
    final seed =
        ref.watch(profileByUsernameProvider(username)).valueOrNull?.avatarId ??
        kDefaultAvatarSeed;

    return BrandSheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarView(
                seed: seed,
                size: 52,
                background: BrandColors.surfaceContainerLow,
                accentColor: BrandColors.primary,
              ),
              const SizedBox(width: BrandSpace.md),
              Expanded(
                child: Text(
                  '@$username invited you',
                  style: BrandText.titleMd.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.md),
          Text(
            'Add @$username as a friend so you can plan trips and ride '
            'together.',
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Add @$username',
            leadingIcon: Icons.person_add_alt_1_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BrandSpace.sm),
          BrandSecondaryButton(
            label: 'Maybe later',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
