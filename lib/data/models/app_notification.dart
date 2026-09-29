/// One entry in the in-app notification feed (`notifications`, written by
/// ranmap-server's `notifyUsers` — see server/src/lib/push.ts).
///
/// This is the durable record of what the user was told; the OS push is a
/// transient tray item that isn't retained. Named `AppNotification` so it can't
/// be confused with Flutter's framework `Notification` class.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.data = const {},
    this.readAt,
    required this.createdAt,
  });

  final String id;

  /// The preference kind it was sent under: `trip_invites`, `chat_messages`,
  /// `trip_updates`, `group_invites` or `convoy_alerts`.
  final String kind;
  final String title;
  final String? body;

  /// The push payload (`type` plus `tripId` / `groupId` / alert `kind`), used to
  /// route a tap to the relevant screen.
  final Map<String, dynamic> data;

  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  String? get tripId => data['tripId'] as String?;
  String? get groupId => data['groupId'] as String?;

  AppNotification markRead(DateTime at) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    data: data,
    readAt: at,
    createdAt: createdAt,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppNotification(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'trip_updates',
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String?,
      data: rawData is Map<String, dynamic> ? rawData : const {},
      readAt: json['read_at'] is String
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      createdAt: json['created_at'] is String
          ? (DateTime.tryParse(json['created_at'] as String) ??
                DateTime.fromMillisecondsSinceEpoch(0))
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
