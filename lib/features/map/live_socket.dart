import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

import '../../core/constants/env.dart';
import '../../data/services/supabase_service.dart';

/// The live-map websocket for one scope (`trip` or `group`).
///
/// The server owns the room (see `server/src/lib/live-rooms.ts`): it verifies
/// the token, checks membership, stamps the sender, and relays positions to the
/// other members of that room. So this side is only a transport — connect, join,
/// send fixes, and hand up whatever frames come back:
///
///   * `joined`   — the join was accepted, with the others' last known positions
///   * `position` — a member moved
///   * `leave`    — a member's socket dropped, so they are offline right now
///
/// A dropped connection reconnects with backoff; the server re-sends a fresh
/// `joined` snapshot each time, which is also what heals a missed frame.
class LiveSocket {
  LiveSocket({required this.scope, required this.id});

  /// `trip` or `group` — the room's scope on the server.
  final String scope;
  final String id;

  final _frames = StreamController<Map<String, dynamic>>.broadcast();

  WebSocket? _socket;
  Timer? _retry;
  int _attempts = 0;
  int? _lastCloseCode;
  bool _joined = false;
  bool _closed = false;

  /// Frames relayed by the server, decoded.
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  /// Whether the server has accepted our join on the current connection.
  bool get joined => _joined;

  /// Opens the socket and asks to join the room. Safe to call repeatedly.
  Future<void> connect() async {
    if (_closed || _socket != null) return;
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    // Signed out: nothing to join. The provider is torn down on sign-out anyway.
    if (token == null) return;
    final url = _url();
    try {
      debugPrint('live socket: dialing $url');
      final socket = await WebSocket.connect(url);
      if (_closed) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      _attempts = 0;
      // The token rides in the join frame rather than the URL, so it isn't
      // written to any access log.
      socket.add(
        jsonEncode({'type': 'join', 'token': token, 'scope': scope, 'id': id}),
      );
      socket.listen(
        _onFrame,
        onDone: () {
          // The close code is the useful part: 4401/4403 mean the server
          // refused the join, 1006 is a dead connection (proxy or TLS).
          debugPrint(
            'live socket: closed code=${socket.closeCode} '
            'reason="${socket.closeReason}"',
          );
          _lastCloseCode = socket.closeCode;
          _onDone();
        },
        onError: (Object error) {
          debugPrint('live socket: error: $error');
          _onDone();
        },
        cancelOnError: true,
      );
    } catch (error) {
      debugPrint('live socket: connect failed for $url: $error');
      _scheduleRetry();
    }
  }

  /// Reports a fix to the room. Dropped silently while offline: positions are
  /// live data and the next fix arrives within a couple of seconds.
  void sendPosition(Position position) {
    final socket = _socket;
    if (socket == null || !_joined) return;
    socket.add(
      jsonEncode({
        'type': 'position',
        'lat': position.latitude,
        'lng': position.longitude,
        // A negative reading is geolocator's "no measurement" sentinel.
        if (position.speed >= 0) 'speedMps': position.speed,
        if (position.heading >= 0) 'heading': position.heading,
      }),
    );
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    final socket = _socket;
    _socket = null;
    _joined = false;
    await socket?.close();
    await _frames.close();
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic>? frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) frame = decoded;
    } catch (_) {
      return; // A frame we can't parse isn't worth a reconnect.
    }
    if (frame == null) return;
    if (frame['type'] == 'joined') {
      _joined = true;
      debugPrint('live socket: joined $scope:$id');
    }
    _frames.add(frame);
  }

  void _onDone() {
    _joined = false;
    _socket = null;
    if (!_closed) _scheduleRetry();
  }

  /// Reconnects with backoff, capped so a long outage isn't a hot loop. The
  /// error is surfaced only after a few attempts, so a brief blip doesn't tell
  /// the user the live map is broken.
  void _scheduleRetry() {
    if (_closed || _retry != null) return;
    _attempts++;
    if (_attempts == 3) {
      _frames.addError(
        StateError('live positions unavailable (code ${_lastCloseCode ?? 'none'})'),
      );
    }
    final seconds = math.min(1 << (_attempts - 1), 15);
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      unawaited(connect());
    });
  }

  /// `ws(s)://…/live` derived from the REST base URL, which may carry the
  /// reverse-proxy path prefix (the server accepts `<prefix>/live` too).
  String _url() {
    final base = Uri.parse(Env.backendUrl);
    var path = base.path;
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '$path/live',
    ).toString();
  }
}
