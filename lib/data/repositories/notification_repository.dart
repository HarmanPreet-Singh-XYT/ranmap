import '../services/supabase_service.dart';

/// The user's notification opt-ins. A missing row means everything is on (the
/// server defaults to sending), so this mirrors the `notification_prefs`
/// defaults.
class NotificationPreferences {
  const NotificationPreferences({
    this.tripInvites = true,
    this.chatMessages = true,
    this.tripUpdates = true,
    this.groupInvites = true,
    this.convoyAlerts = true,
  });

  final bool tripInvites;
  final bool chatMessages;
  final bool tripUpdates;
  final bool groupInvites;
  final bool convoyAlerts;

  factory NotificationPreferences.fromRow(Map<String, dynamic> row) =>
      NotificationPreferences(
        tripInvites: row['trip_invites'] as bool? ?? true,
        chatMessages: row['chat_messages'] as bool? ?? true,
        tripUpdates: row['trip_updates'] as bool? ?? true,
        groupInvites: row['group_invites'] as bool? ?? true,
        convoyAlerts: row['convoy_alerts'] as bool? ?? true,
      );

  NotificationPreferences copyWith({
    bool? tripInvites,
    bool? chatMessages,
    bool? tripUpdates,
    bool? groupInvites,
    bool? convoyAlerts,
  }) => NotificationPreferences(
    tripInvites: tripInvites ?? this.tripInvites,
    chatMessages: chatMessages ?? this.chatMessages,
    tripUpdates: tripUpdates ?? this.tripUpdates,
    groupInvites: groupInvites ?? this.groupInvites,
    convoyAlerts: convoyAlerts ?? this.convoyAlerts,
  );
}

/// Reads and writes the owner's `notification_prefs` row. RLS scopes both to
/// the signed-in user (see 0011_notifications.sql).
class NotificationRepository {
  final _client = SupabaseService.client;

  Future<NotificationPreferences> fetch() async {
    final uid = SupabaseService.currentUserId;
    final row = await _client
        .from('notification_prefs')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row == null
        ? const NotificationPreferences()
        : NotificationPreferences.fromRow(row);
  }

  Future<void> save(NotificationPreferences prefs) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('notification_prefs').upsert({
      'user_id': uid,
      'trip_invites': prefs.tripInvites,
      'chat_messages': prefs.chatMessages,
      'trip_updates': prefs.tripUpdates,
      'group_invites': prefs.groupInvites,
      'convoy_alerts': prefs.convoyAlerts,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
