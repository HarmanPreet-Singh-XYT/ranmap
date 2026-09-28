/// A file in the user's private document wallet (license, insurance, tickets).
class UserDocument {
  const UserDocument({
    required this.id,
    required this.name,
    required this.kind,
    required this.storagePath,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String name;

  /// `license` | `insurance` | `ticket` | `registration` | `other`.
  final String kind;
  final String storagePath;
  final DateTime createdAt;
  final DateTime? expiresAt;

  factory UserDocument.fromJson(Map<String, dynamic> json) => UserDocument(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String? ?? 'other',
    storagePath: json['storage_path'] as String,
    createdAt: json['created_at'] is String
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.fromMillisecondsSinceEpoch(0),
    expiresAt: json['expires_at'] != null
        ? DateTime.parse(json['expires_at'] as String)
        : null,
  );
}
