/// What a chat message carries. `text` is a plain message; the rest are "rich"
/// messages whose details live in [ChatMessage.payload] (and whose [body] holds a
/// plain-text fallback, so push previews and older clients still read sensibly).
enum ChatMessageKind {
  text('text'),
  photo('photo'),
  location('location'),
  trip('trip');

  const ChatMessageKind(this.wire);
  final String wire;

  static ChatMessageKind fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    // A kind from a newer app version degrades to plain text (its body is a
    // readable fallback) rather than breaking the thread.
    return ChatMessageKind.text;
  }
}

class ChatMessage {
  final String id;
  final String? tripId;
  final String? groupId;
  final String? conversationId;
  final String senderId;
  final String? body;
  final DateTime createdAt;
  final String? senderUsername;
  final ChatMessageKind kind;
  final Map<String, dynamic>? payload;

  const ChatMessage({
    required this.id,
    this.tripId,
    this.groupId,
    this.conversationId,
    required this.senderId,
    this.body,
    required this.createdAt,
    this.senderUsername,
    this.kind = ChatMessageKind.text,
    this.payload,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return ChatMessage(
      id: json['id'] as String,
      tripId: json['trip_id'] as String?,
      groupId: json['group_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      senderId: json['sender_id'] as String,
      body: json['body'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderUsername:
          (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
      kind: ChatMessageKind.fromWire(json['kind'] as String?),
      payload: rawPayload is Map ? rawPayload.cast<String, dynamic>() : null,
    );
  }

  /// The ids of the photos a `photo` message points at.
  List<String> get photoPostIds {
    final posts = payload?['posts'];
    if (posts is! List) return const [];
    return [
      for (final p in posts)
        if (p is Map && p['id'] is String) p['id'] as String,
    ];
  }

  double? get payloadLat => (payload?['lat'] as num?)?.toDouble();
  double? get payloadLng => (payload?['lng'] as num?)?.toDouble();
  String? get payloadName => payload?['name'] as String?;
  String? get payloadTripId => payload?['trip_id'] as String?;
  String? get payloadTripTitle => payload?['title'] as String?;
}

/// One entry of the direct-message inbox (`my_conversations()`).
class DirectConversation {
  const DirectConversation({
    required this.id,
    required this.otherId,
    required this.username,
    this.displayName,
    this.avatarId = 'default',
    this.lastBody,
    this.lastKind = ChatMessageKind.text,
    this.lastSenderId,
    required this.lastAt,
  });

  final String id;
  final String otherId;
  final String username;
  final String? displayName;
  final String avatarId;
  final String? lastBody;
  final ChatMessageKind lastKind;
  final String? lastSenderId;
  final DateTime lastAt;

  /// What to call the other person in lists and the chat header.
  String get title =>
      (displayName?.isNotEmpty ?? false) ? displayName! : '@$username';

  factory DirectConversation.fromJson(Map<String, dynamic> json) =>
      DirectConversation(
        id: json['conversation_id'] as String,
        otherId: json['other_id'] as String,
        username: json['username'] as String? ?? 'someone',
        displayName: json['display_name'] as String?,
        avatarId: json['avatar_id'] as String? ?? 'default',
        lastBody: json['last_body'] as String?,
        lastKind: ChatMessageKind.fromWire(json['last_kind'] as String?),
        lastSenderId: json['last_sender'] as String?,
        lastAt: DateTime.parse(json['last_at'] as String),
      );
}
