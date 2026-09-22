import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/outbox_providers.dart';
import '../providers/connectivity_provider.dart';
import '../theme/app_theme.dart';

/// Wraps the app and shows a thin banner while offline or while queued writes
/// are still syncing, so the user understands the state of their data instead
/// of assuming it saved. Pushes content down rather than overlaying it.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeping the drain provider alive means the outbox replays on start and
    // whenever connectivity returns, for the whole app lifetime.
    ref.watch(outboxDrainProvider);
    final offline = ref.watch(isOfflineProvider);
    final pending = ref.watch(outboxProvider).pending;

    return ValueListenableBuilder<int>(
      valueListenable: pending,
      builder: (context, count, _) {
        final showStrip = offline || count > 0;
        return Column(
          children: [
            if (offline)
              _Strip(
                color: AppTheme.danger,
                icon: Icons.cloud_off_rounded,
                text: count > 0
                    ? "You're offline — $count change${count == 1 ? '' : 's'} will sync when you reconnect."
                    : "You're offline — changes will sync when you reconnect.",
              )
            else if (count > 0)
              _Strip(
                color: AppTheme.secondary,
                icon: Icons.sync_rounded,
                text: 'Syncing $count pending change${count == 1 ? '' : 's'}…',
              ),
            Expanded(
              // The strip already paints the status-bar area, so stop the app
              // bar below it from adding that inset a second time.
              child: showStrip
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: child,
                    )
                  : child,
            ),
          ],
        );
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
