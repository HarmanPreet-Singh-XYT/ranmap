import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/app_toast.dart';

/// Opens the platform's subscription-management screen — the store page where a
/// subscriber can change or cancel their plan.
///
/// Ship-together with the paywall so the "Manage Subscription" action is the
/// same everywhere it's offered (the paywall, and now Settings/Profile for an
/// existing Pro user, who otherwise had no in-app way back to it).
Future<void> openManageSubscription(BuildContext context) async {
  final uri = Uri.parse(
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions',
  );
  if (!await canLaunchUrl(uri)) {
    if (context.mounted) {
      showAppToast(context, 'Could not open subscription settings', error: true);
    }
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
