/// A tool the assistant actually executed this turn, with its real result.
/// Shown as a receipt so the user can see exactly what ran.
class AiToolReceipt {
  const AiToolReceipt({required this.name, this.result});

  final String name;
  final Object? result;

  factory AiToolReceipt.fromJson(Map<String, dynamic> json) => AiToolReceipt(
    name: json['name'] as String? ?? 'action',
    result: json['result'],
  );

  /// Whether the tool reported success (its result carries no `error`).
  bool get ok {
    final r = result;
    return !(r is Map && r['error'] != null);
  }

  /// A short label derived from the tool name.
  String get title => switch (name) {
    'save_place' => ok ? 'Saved a place' : 'Couldn’t save a place',
    'create_trip' => ok ? 'Created a trip' : 'Couldn’t create a trip',
    'schedule_trip' => ok ? 'Scheduled a trip' : 'Couldn’t schedule a trip',
    'invite_friend_to_trip' =>
      ok ? 'Invited a friend' : 'Couldn’t invite a friend',
    'add_stop' => ok ? 'Added a stop' : 'Couldn’t add a stop',
    _ => ok ? 'Ran $name' : '$name failed',
  };

  /// The real detail from the tool's result (place name, trip title, …).
  String? get detail {
    final r = result;
    if (r is! Map) return null;
    if (r['error'] != null) return r['error'].toString();
    for (final key in const [
      'saved',
      'title',
      'trip_title',
      'stop',
      'username',
    ]) {
      final v = r[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }
}

class AiMessage {
  final String id;
  final String conversationId;
  final String role; // user | assistant
  final String content;
  final DateTime createdAt;

  /// Tools the assistant executed for this reply (empty for user messages and
  /// plain replies).
  final List<AiToolReceipt> tools;

  const AiMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.tools = const [],
  });

  bool get isUser => role == 'user';

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    tools:
        (json['tools'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(AiToolReceipt.fromJson)
            .toList() ??
        const [],
  );
}
