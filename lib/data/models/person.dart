/// How the current user knows someone, strongest first. Mirrors the
/// `relationship` column of `people_around_me()` (0050).
enum PersonRelationship {
  /// Accepted friends either way.
  friend,

  /// On a trip that is running right now.
  riding,

  /// Been on a trip together, but nothing is running.
  travelled,

  /// In a group together.
  group;

  static PersonRelationship fromWire(String? value) => switch (value) {
    'friend' => PersonRelationship.friend,
    'riding' => PersonRelationship.riding,
    'group' => PersonRelationship.group,
    _ => PersonRelationship.travelled,
  };

  /// Short label for the row's tag.
  String get label => switch (this) {
    PersonRelationship.friend => 'Friend',
    PersonRelationship.riding => 'Riding now',
    PersonRelationship.travelled => 'Rode together',
    PersonRelationship.group => 'Group',
  };
}

/// One person the user shares some context with, as `people_around_me()` sees
/// them: who they are, why they're here, and whether they may be messaged.
class Person {
  const Person({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarId = 'default',
    this.vehicleType,
    this.relationship = PersonRelationship.travelled,
    this.isFriend = false,
    this.canMessage = false,
  });

  final String userId;
  final String? username;
  final String? displayName;
  final String avatarId;
  final String? vehicleType;
  final PersonRelationship relationship;

  /// Whether the friendship is accepted (not merely requested).
  final bool isFriend;

  /// Whether a DM may be started: friends always, anyone else only if they
  /// allow messages from strangers.
  final bool canMessage;

  /// What to show on the row.
  String get label =>
      (username != null && username!.isNotEmpty) ? '@$username' : 'Someone';

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    userId: json['user_id'] as String,
    username: json['username'] as String?,
    displayName: json['display_name'] as String?,
    avatarId: json['avatar_id'] as String? ?? 'default',
    vehicleType: json['vehicle_type'] as String?,
    relationship: PersonRelationship.fromWire(json['relationship'] as String?),
    isFriend: json['is_friend'] as bool? ?? false,
    canMessage: json['can_message'] as bool? ?? false,
  );
}
