import 'package:flutter/material.dart';

import '../offline/outbox.dart';
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
