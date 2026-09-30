import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/supabase_service.dart';

/// The kinds of writes the outbox knows how to replay. Each maps to a table
/// whose primary key is client-supplied, so the *same* id is used on the online
/// attempt and any queued replay — replay is then idempotent
/// (`upsert … ignoreDuplicates`) and a lost response can't duplicate the row.
enum OutboxType {
  chatMessage('chat_message'),
  tripExpense('trip_expense'),
  tripStop('trip_stop');

  const OutboxType(this.wire);
  final String wire;

  static OutboxType? fromWire(String value) {
    for (final type in OutboxType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// A write that couldn't reach the server (device offline or a network error),
/// queued to be replayed once connectivity returns.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.userId,
  });

  /// Client-generated UUID, used as the row's primary key on both the online
  /// attempt and replay.
  final String id;
  final OutboxType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// How many times a replay has been attempted and reported as retryable. A
  /// persistently "retryable" error (one the classifier can't place) would
  /// otherwise block the queue forever, so attempts are bounded.
  final int attempts;

  /// The account that queued the write (stamped on enqueue). A queued write is
  /// only ever replayed by that same account — never re-attributed to whoever
  /// signs in next on the device. Null for entries queued before this existed.
  final String? userId;

  OutboxEntry withAttempts(int value) => OutboxEntry(
        id: id,
        type: type,
        payload: payload,
        createdAt: createdAt,
        attempts: value,
        userId: userId,
      );

  OutboxEntry withUser(String? value) => OutboxEntry(
        id: id,
        type: type,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts,
        userId: value,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        if (userId != null) 'user_id': userId,
      };

  static OutboxEntry? fromJson(Map<String, dynamic> json) {
    final type = OutboxType.fromWire(json['type'] as String? ?? '');
    if (type == null) return null;
    final id = json['id'];
    final payload = json['payload'];
    final createdAt = json['created_at'];
    if (id is! String || payload is! Map || createdAt is! String) return null;
    return OutboxEntry(
      id: id,
      type: type,
      payload: payload.cast<String, dynamic>(),
      createdAt: DateTime.parse(createdAt),
      attempts: json['attempts'] is int ? json['attempts'] as int : 0,
      userId: json['user_id'] is String ? json['user_id'] as String : null,
    );
  }
}

/// The signed-in user's id, or null when there's no session (or Supabase isn't
/// initialised, as in unit tests).
String? _currentUid() {
  try {
    return SupabaseService.currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// A small persisted FIFO of pending writes. Only queued operations are stored,
/// not a copy of server data.
class Outbox {
  static const _storageKey = 'outbox_v1';
  static const _failedStorageKey = 'outbox_failed_v1';

  /// Upper bound on queued writes. A long offline stretch must not grow the
  /// persisted queue without limit; past this the oldest entry is dropped (and
  /// surfaced as a failure so the user is told).
  static const _maxEntries = 500;

  /// Upper bound on retained failure notices.
  static const _maxFailed = 50;

  /// How many *retryable* attempts an entry gets before it's given up on. A
  /// persistently-misclassified failure would otherwise block every write
  /// behind it forever.
  static const maxAttempts = 20;

  /// Number of writes still waiting to sync; watch it to surface a badge.
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  /// Writes that were permanently rejected (RLS denial, validation failure)
  /// and dropped from the queue without ever reaching the server. Kept here —
  /// not just logged — so the UI can tell the user their change was lost
  /// instead of silently discarding it. Cleared via [acknowledgeFailed].
  final ValueNotifier<List<OutboxEntry>> failed = ValueNotifier<List<OutboxEntry>>(const []);

  /// True while a drain pass is running (guards against overlapping drains of
  /// the same outbox).
  bool draining = false;

  final List<OutboxEntry> _entries = [];
  Future<void>? _loading;
  // Serializes persistence so concurrent enqueue/remove can't clobber each
  // other's snapshot of the list.
  Future<void> _writeQueue = Future.value();

  Future<void> _ensureLoaded() {
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    // If loading fails, clear the cached future so a later call can retry
    // instead of the queue being poisoned forever. The handler also marks the
    // error as observed so it can't surface as an unhandled async error.
    future.catchError((Object e) {
      if (identical(_loading, future)) _loading = null;
      debugPrint('outbox: load failed: $e');
    });
    return future;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    var dropped = false;
    _entries.clear();
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          dropped = true;
          continue;
        }
        final entry = OutboxEntry.fromJson(decoded);
        if (entry != null) {
          _entries.add(entry);
        } else {
          dropped = true;
        }
      } catch (_) {
        // A corrupt line shouldn't brick the whole queue; skip it.
        dropped = true;
      }
    }
    pending.value = _entries.length;

    // Restore surfaced failures so the "couldn't be saved" notice survives a
    // restart instead of disappearing without the user ever seeing it.
    final failedRaw = prefs.getStringList(_failedStorageKey) ?? const [];
    final restored = <OutboxEntry>[];
    for (final line in failedRaw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          final entry = OutboxEntry.fromJson(decoded);
          if (entry != null) restored.add(entry);
        }
      } catch (_) {
        // Skip corrupt failure lines.
      }
    }
    failed.value = restored;

    if (dropped) {
      // Rewrite without the bad lines so they don't linger forever.
      _writeQueue = _writeQueue.then((_) => _write(prefs)).catchError((Object _) {});
    }
  }

  Future<void> _write(SharedPreferences prefs) async {
    await prefs.setStringList(_storageKey, [for (final e in _entries) jsonEncode(e.toJson())]);
    pending.value = _entries.length;
  }

  Future<void> _persistFailed(SharedPreferences prefs) async {
    await prefs.setStringList(
      _failedStorageKey,
      [for (final e in failed.value) jsonEncode(e.toJson())],
    );
  }

  Future<void> _persist() async {
    await _ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    // Chain onto the previous write so snapshots are applied in order. The
    // catchError keeps the chain alive after a failed write (otherwise a single
    // error would permanently reject every later enqueue/remove).
    _writeQueue = _writeQueue.then((_) => _write(prefs)).catchError((Object e) {
      debugPrint('outbox: persist failed: $e');
    });
    await _writeQueue;
  }

  Future<void> enqueue(OutboxEntry entry) async {
    await _ensureLoaded();
    // Bound the queue: drop the oldest entry (recording it as lost so the user
    // is told) rather than growing the persisted list without limit.
    if (_entries.length >= _maxEntries) {
      final dropped = _entries.removeAt(0);
      failed.value = [
        ...failed.value,
        dropped,
      ].take(_maxFailed).toList();
      unawaited(_persistFailures());
    }
    _entries.add(entry.userId == null
        ? entry.withUser(_currentUid())
        : entry);
    await _persist();
  }

  /// Entries the signed-in account may replay: its own, plus legacy ones with no
  /// owner recorded. Another account's queued writes stay put (untouched) until
  /// that account signs back in.
  Future<List<OutboxEntry>> allForCurrentUser() async {
    await _ensureLoaded();
    final uid = _currentUid();
    if (uid == null) return const [];
    return [
      for (final e in _entries)
        if (e.userId == null || e.userId == uid) e,
    ];
  }

  Future<List<OutboxEntry>> all() async {
    await _ensureLoaded();
    return List.of(_entries);
  }

  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.id == id);
    await _persist();
  }

  /// Records another failed (retryable) attempt for [id] and returns the new
  /// count. Returns 0 when the entry is gone.
  Future<int> bumpAttempt(String id) async {
    await _ensureLoaded();
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return 0;
    final updated = _entries[index].withAttempts(_entries[index].attempts + 1);
    _entries[index] = updated;
    await _persist();
    return updated.attempts;
  }

  /// Records that [entry] was permanently rejected and removed from the
  /// queue, so the UI can surface the loss instead of it vanishing silently.
  void recordFailed(OutboxEntry entry) {
    failed.value = [...failed.value, entry].take(_maxFailed).toList();
    unawaited(_persistFailures());
  }

  /// Dismisses all currently-surfaced failures once the user has seen them.
  void acknowledgeFailed() {
    failed.value = const [];
    unawaited(_persistFailures());
  }

  Future<void> _persistFailures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistFailed(prefs);
    } catch (e) {
      debugPrint('outbox: persist failures failed: $e');
    }
  }

  /// Drops every queued (not-yet-synced) write and clears surfaced failures.
  /// Exposed for Settings → Clear offline queue; the caller must confirm first,
  /// since the queued writes are permanently lost.
  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    failed.value = const [];
    await _persist();
    await _persistFailures();
  }
}

/// True when [error] looks like a connectivity problem (worth retrying).
bool isNetworkError(Object error) =>
    error is SocketException || error is TimeoutException || error is http.ClientException;

// PostgREST/Postgres error codes that are transient (server-side / overloaded)
// rather than a permanent rejection.
const _transientPgCodes = {
  '57014', // statement timeout
  '53300', // too many connections
  '57P01', // admin shutdown
  '57P02', // crash shutdown
  '57P03', // cannot connect now
  '08000', '08001', '08003', '08004', '08006', // connection exceptions
};

/// Whether an outbox entry failure should be retried later (true) or dropped as
/// permanent (false). Erring toward retry avoids silently losing data.
bool isRetryableOutboxError(Object error) {
  if (isNetworkError(error)) return true;
  // A malformed persisted payload (e.g. a cast that throws) is a bug in the
  // entry itself, not a transient failure — retrying it forever would block
  // every write behind it, so treat it as permanent.
  if (error is TypeError ||
      error is StateError ||
      error is FormatException ||
      error is ArgumentError) {
    return false;
  }
  if (error is PostgrestException) {
    final code = error.code;
    // A concrete, non-transient SQLSTATE / PGRST code is a permanent rejection
    // (RLS denial, constraint violation, "no rows", …).
    if (code != null && code.isNotEmpty) return _transientPgCodes.contains(code);
    // No code — likely a transport/service failure; retry.
    return true;
  }
  if (error is AuthException) return true;
  // Unknown failures (e.g. session not yet hydrated) are worth another try.
  return true;
}

/// RFC 4122 v4 UUID from a secure RNG (no dependency needed for this one call).
String generateUuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
