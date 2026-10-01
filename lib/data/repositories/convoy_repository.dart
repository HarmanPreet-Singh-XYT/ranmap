import 'dart:async';

import '../../core/network/backend_client.dart';
import '../models/group_alert.dart';
import '../services/supabase_service.dart';

/// Group-scoped live convoy: presence positions and convoy alerts (SOS,
/// regroup, arrival check-ins). See `0027_group_convoy.sql`.
class ConvoyRepository {
  final _client = SupabaseService.client;

  /// Publishes this device's position to the group's convoy channel. The
  /// server stamps the sender id, so a client can't forge another member's
  /// position. Nothing is persisted: group presence lives only on the channel.
  Future<void> broadcastPosition({
    required String groupId,
    required double lat,
    required double lng,
    double? speedMps,
    double? heading,
  }) async {
    await _client.rpc(
      'broadcast_group_position',
      params: {
        'p_group': groupId,
        'p_lat': lat,
        'p_lng': lng,
        'p_speed': speedMps,
        'p_heading': heading,
        'p_persist': false,
      },
    );
  }

  /// The group's alerts, newest first, each with its arrival check-ins and the
  /// creator's handle.
  Future<List<GroupAlert>> fetchAlerts(String groupId, {int limit = 40}) async {
    final rows = await _client
        .from('group_alerts')
        .select(
          '*, creator:profiles!group_alerts_created_by_fkey(username, avatar_id), '
          'alert_checkins(user_id, arrived_at, departed_at)',
        )
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => GroupAlert.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Raises an alert and, best-effort, pushes it to the rest of the group
  /// (the server re-checks membership before sending).
  Future<GroupAlert> sendAlert({
    required String groupId,
    required GroupAlertKind kind,
    String? message,
    double? lat,
    double? lng,
  }) async {
    final data = await _client.rpc(
      'send_group_alert',
      params: {
        'p_group': groupId,
        'p_kind': kind.wire,
        'p_message': message,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    final row = data is List
        ? data.first as Map<String, dynamic>
        : data as Map<String, dynamic>;
    final alert = GroupAlert.fromJson(row);
    unawaited(_notifyAlert(alert.id));
    return alert;
  }

  /// Marks the caller as arrived at / departed from a rendezvous alert.
  Future<void> checkIn({required String alertId, required bool arrived}) async {
    await _client.rpc(
      'check_in_alert',
      params: {'p_alert': alertId, 'p_arrived': arrived},
    );
  }

  /// Resolves (closes) an alert. Admin-only, enforced by the RPC.
  Future<void> resolveAlert(String alertId) async {
    await _client.rpc('resolve_group_alert', params: {'p_alert': alertId});
  }

  Future<void> _notifyAlert(String alertId) async {
    try {
      await BackendClient.postJson('/notifications/group-alert', {
        'alertId': alertId,
      }, fallbackMessage: 'Could not send the convoy alert');
    } catch (_) {
      // Best-effort: the alert is already visible in-app.
    }
  }
}
