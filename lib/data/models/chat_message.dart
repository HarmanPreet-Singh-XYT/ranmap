class ChatMessage {
  final String id;
  final String? tripId;
  final String? groupId;
  final String senderId;
  final String? body;
  final DateTime createdAt;
  final String? senderUsername;

  const ChatMessage({
    required this.id,
    this.tripId,
    this.groupId,
    required this.senderId,
    this.body,
    required this.createdAt,
    this.senderUsername,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        tripId: json['trip_id'] as String?,
        groupId: json['group_id'] as String?,
        senderId: json['sender_id'] as String,
        body: json['body'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        senderUsername:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
      );
}
