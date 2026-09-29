import '../models/app_notification.dart';
import '../services/supabase_service.dart';

/// The in-app notification feed (`notifications`). Rows are authored only by
/// ranmap-server; the client reads its own (RLS), marks them read, and deletes
/// them (see 0039_notifications_feed.sql).
class NotificationsFeedRepository {
  final _client = SupabaseService.client;

  /// Recent notifications for the current user, newest first.
  Future<List<AppNotification>> fetchNotifications({int limit = 100}) async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AppNotification.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// How many notifications are unread. Fetches only ids, so the payload stays
  /// small even for a busy account.
  Future<int> unreadCount() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return 0;
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .isFilter('read_at', null);
    return (rows as List).length;
  }

  Future<void> markRead(String id) async {
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> markAllRead() async {
    final uid = SupabaseService.currentUserId;
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .isFilter('read_at', null);
  }

  Future<void> deleteNotification(String id) async {
    await _client.from('notifications').delete().eq('id', id);
  }
}
