import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  /// Client-generated UUID, used as the row's primary key on both the online
  /// attempt and replay.
  final String id;
  final OutboxType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wire,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
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
    );
  }
}

/// A small persisted FIFO of pending writes. Only queued operations are stored,
/// not a copy of server data.
class Outbox {
  static const _storageKey = 'outbox_v1';

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

  Future<void> _ensureLoaded() => _loading ??= _load();

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
    if (dropped) {
      // Rewrite without the bad lines so they don't linger forever.
      _writeQueue = _writeQueue.then((_) => _write(prefs));
    }
  }

  Future<void> _write(SharedPreferences prefs) async {
    await prefs.setStringList(_storageKey, [for (final e in _entries) jsonEncode(e.toJson())]);
    pending.value = _entries.length;
  }

  Future<void> _persist() async {
    await _ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    // Chain onto the previous write so snapshots are applied in order.
    _writeQueue = _writeQueue.then((_) => _write(prefs));
    await _writeQueue;
  }

  Future<void> enqueue(OutboxEntry entry) async {
    await _ensureLoaded();
    _entries.add(entry);
    await _persist();
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

  /// Records that [entry] was permanently rejected and removed from the
  /// queue, so the UI can surface the loss instead of it vanishing silently.
  void recordFailed(OutboxEntry entry) {
    failed.value = [...failed.value, entry];
  }

  /// Dismisses all currently-surfaced failures once the user has seen them.
  void acknowledgeFailed() {
    failed.value = const [];
  }

  /// Drops every queued (not-yet-synced) write and clears surfaced failures.
  /// Exposed for Settings → Clear offline queue; the caller must confirm first,
  /// since the queued writes are permanently lost.
  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    failed.value = const [];
    await _persist();
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
