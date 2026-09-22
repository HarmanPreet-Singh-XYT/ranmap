class AiConversation {
  final String id;
  final String title;
  final DateTime createdAt;

  const AiConversation({required this.id, required this.title, required this.createdAt});

  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
        id: json['id'] as String,
        title: (json['title'] as String?)?.trim().isNotEmpty == true
            ? json['title'] as String
            : 'New conversation',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
