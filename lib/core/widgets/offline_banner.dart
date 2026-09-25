import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../offline/outbox.dart';
import '../offline/outbox_providers.dart';
import '../providers/connectivity_provider.dart';
import '../theme/nav_palette.dart';

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
    final outbox = ref.watch(outboxProvider);
    final c = NavColors.of(context);

    return ValueListenableBuilder<int>(
      valueListenable: outbox.pending,
      builder: (context, count, _) {
        return ValueListenableBuilder<List<OutboxEntry>>(
          valueListenable: outbox.failed,
          builder: (context, failedEntries, _) {
            final showStrip = offline || count > 0 || failedEntries.isNotEmpty;
            return Column(
              children: [
                if (failedEntries.isNotEmpty)
                  _Strip(
                    color: c.destructive,
                    foreground: Colors.white,
                    icon: Icons.error_outline_rounded,
                    text: failedEntries.length == 1
                        ? "1 change couldn't be saved and was lost. Please try again."
                        : "${failedEntries.length} changes couldn't be saved and were lost. Please try again.",
                    onDismiss: outbox.acknowledgeFailed,
                  )
                else if (offline)
                  _Strip(
                    color: c.destructive,
                    foreground: Colors.white,
                    icon: Icons.cloud_off_rounded,
                    text: count > 0
                        ? "You're offline — $count change${count == 1 ? '' : 's'} will sync when you reconnect."
                        : "You're offline — changes will sync when you reconnect.",
                  )
                else if (count > 0)
                  _Strip(
                    color: c.activeRoute,
                    foreground: Colors.white,
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
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.text,
    this.onDismiss,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String text;
  final VoidCallback? onDismiss;

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
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: foreground, fontSize: 13)),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: foreground),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
