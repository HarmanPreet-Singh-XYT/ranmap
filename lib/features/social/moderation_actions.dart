import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/error_text.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_toast.dart';
import 'social_providers.dart';

/// The reasons a user can pick when reporting, mapped to the values the server
/// accepts (`reason` check constraint in 0046_moderation.sql).
const List<({String value, String label})> kReportReasons = [
  (value: 'spam', label: 'Spam or scam'),
  (value: 'harassment', label: 'Harassment or hate'),
  (value: 'explicit', label: 'Nudity or sexual content'),
  (value: 'violence', label: 'Violence or dangerous content'),
  (value: 'other', label: 'Something else'),
];

/// Opens the report flow for a piece of content and files it. [targetType] is
/// one of `user`, `message`, `post`, `group`.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
  String title = 'Report',
}) async {
  final reason = await showAppChoiceSheet<String>(
    context,
    title: title,
    options: kReportReasons,
  );
  if (reason == null || !context.mounted) return;
  try {
    await ref
        .read(moderationRepositoryProvider)
        .reportContent(
          targetType: targetType,
          targetId: targetId,
          reason: reason,
        );
    if (context.mounted) {
      showAppToast(context, 'Thanks — our team will review this.');
    }
  } catch (e) {
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}

/// Confirms and performs a block. Blocking removes any friendship and closes
/// the direct-message thread server-side.
Future<void> showBlockUserConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String username,
}) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Block @$username?',
    message:
        'They won\'t be able to message you or send friend requests, and any '
        'friendship is removed. You can unblock them later in Settings.',
    confirmLabel: 'Block',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ref.read(moderationRepositoryProvider).blockUser(userId);
    ref.invalidate(friendsProvider);
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(outgoingRequestsProvider);
    ref.invalidate(blockedUsersProvider);
    if (context.mounted) showAppToast(context, '@$username blocked.');
  } catch (e) {
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}
