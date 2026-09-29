import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/invite_links.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/widgets/app_toast.dart';

/// Shares the signed-in user's personal invite link through the system share
/// sheet — the one entry point every "Invite" affordance in the app routes
/// through, so the copy and the link format stay in one place.
///
/// The link uses [inviteLinkFor], which falls back to the app's registered
/// custom scheme until the production domain is live, so sharing works today
/// instead of shipping a dead `https://<placeholder>` URL.
///
/// [intro] is an optional sentence prepended above the handle + link (e.g. a
/// trip-specific `Join me for <trip>`). Returns true when the sheet was shown.
Future<bool> shareMyInviteLink(
  BuildContext context,
  WidgetRef ref, {
  String? intro,
}) async {
  final handle = ref.read(myProfileProvider).valueOrNull?.username;
  if (handle == null || handle.isEmpty) {
    showAppToast(context, 'Set a username before inviting people.', error: true);
    return false;
  }

  final text = [
    if (intro != null && intro.isNotEmpty) intro,
    'Add me on Ranmap — my username is @$handle.',
    inviteLinkFor(handle),
  ].join('\n');

  try {
    await SharePlus.instance.share(
      ShareParams(subject: 'Join me on Ranmap', text: text),
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      showAppToast(context, 'Could not open sharing.', error: true);
    }
    return false;
  }
}
