import 'package:flutter/material.dart';

import '../feedback/app_feedback.dart';
import '../theme/brand_palette.dart';

/// Swipe-down-to-reload for a scrollable [child], the app's one standard
/// gesture for "get me the latest". Realtime keeps most data live; this is the
/// manual escape hatch for a flaky connection or a missed event.
///
/// The child's scroll view should use [AlwaysScrollableScrollPhysics] so short
/// lists (and empty states) can still be pulled. A failed refresh is swallowed:
/// the provider's own error state already tells the user.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: BrandColors.primary,
      onRefresh: () async {
        AppFeedback.refresh();
        try {
          await onRefresh();
        } catch (_) {}
      },
      child: child,
    );
  }
}
