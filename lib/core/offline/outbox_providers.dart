import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../features/chat/chat_providers.dart';
import '../../features/trip/trip_providers.dart';
import '../providers/connectivity_provider.dart';
import 'outbox.dart';

/// The singleton outbox of pending offline writes.
final outboxProvider = Provider<Outbox>((ref) => Outbox());

/// Drains the outbox on startup, whenever connectivity returns, and on a
/// periodic sweep (so a failure not accompanied by a connectivity event still
/// eventually syncs). Kept alive by watching it from the app shell.
final outboxDrainProvider = Provider<void>((ref) {
  final outbox = ref.watch(outboxProvider);

  ref.listen(connectivityProvider, (_, next) {
    if (next.valueOrNull == true) unawaited(_drain(ref, outbox));
  });

  final sweep = Timer.periodic(const Duration(seconds: 20), (_) {
    if (outbox.pending.value > 0) unawaited(_drain(ref, outbox));
  });
  ref.onDispose(sweep.cancel);

  unawaited(_drain(ref, outbox));
});

/// A trigger for an immediate outbox drain, for the offline-queue screen's
/// "Retry now" action. Bound to a provider `Ref` (not the widget's), so the
/// drain can invalidate the same providers the background sweep does.
final outboxDrainNowProvider = Provider<Future<void> Function()>((ref) {
  return () => _drain(ref, ref.read(outboxProvider));
});

Future<void> _drain(Ref ref, Outbox outbox) async {
  if (outbox.draining) return;
  outbox.draining = true;
  try {
    final entries = await outbox.all();
    for (final entry in entries) {
      try {
        switch (entry.type) {
          case OutboxType.chatMessage:
            await ChatRepository().sendMessage(
              id: entry.id,
              tripId: entry.payload['trip_id'] as String?,
              groupId: entry.payload['group_id'] as String?,
              body: entry.payload['body'] as String,
            );
            _invalidateChat(ref, entry.payload);
          case OutboxType.tripExpense:
            await TripRepository().replayExpense(entry.id, entry.payload);
            final tripId = entry.payload['trip_id'] as String?;
            if (tripId != null) ref.invalidate(tripExpensesProvider(tripId));
          case OutboxType.tripStop:
            await TripRepository().replayStop(entry.id, entry.payload);
            final tripId = entry.payload['trip_id'] as String?;
            if (tripId != null) ref.invalidate(tripStopsProvider(tripId));
        }
        await outbox.remove(entry.id);
      } catch (error) {
        if (isRetryableOutboxError(error)) {
          // Still offline / transient. Bound the retries so an error the
          // classifier can't place can't block every write behind it forever.
          final attempts = await outbox.bumpAttempt(entry.id);
          if (attempts >= Outbox.maxAttempts) {
            debugPrint(
              'outbox: giving up on ${entry.type.wire} ${entry.id} after $attempts attempts: $error',
            );
            outbox.recordFailed(entry);
            await outbox.remove(entry.id);
            continue;
          }
          // Leave this and everything after it queued; the sweep retries.
          break;
        }
        // A permanent error (RLS, validation) would wedge the queue, so drop
        // just this entry — but record it so the UI can tell the user their
        // change was lost instead of it vanishing without a trace.
        debugPrint('outbox: dropping ${entry.type.wire} ${entry.id}: $error');
        outbox.recordFailed(entry);
        await outbox.remove(entry.id);
      }
    }
  } finally {
    outbox.draining = false;
  }
}

void _invalidateChat(Ref ref, Map<String, dynamic> payload) {
  final tripId = payload['trip_id'] as String?;
  final groupId = payload['group_id'] as String?;
  if (tripId != null) {
    ref.invalidate(chatMessagesProvider(ChatChannel.trip(tripId)));
  } else if (groupId != null) {
    ref.invalidate(chatMessagesProvider(ChatChannel.group(groupId)));
  }
}
