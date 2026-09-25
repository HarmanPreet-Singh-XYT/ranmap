import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../offline/outbox.dart';
import '../theme/nav_palette.dart';
import '../util/error_text.dart';

/// Standard error state with a retry affordance, so a failed load isn't a dead
/// end the user can only escape by leaving and re-entering the screen.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // friendlyError passes raw strings through, which for a SocketException is
    // ugly — and that's the most common reason this widget is shown.
    final message = isNetworkError(error)
        ? "Couldn't reach the server — check your connection and try again."
        : friendlyError(error);
    final c = NavColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: c.mutedForeground),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.destructive),
              ),
            ),
            const SizedBox(height: 20),
            FButton(onPress: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
