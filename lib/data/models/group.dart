class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerId,
    this.description,
    this.avatarId = 'default',
    this.inviteCode,
    this.inviteRequiresApproval = false,
  });

  final String id;
  final String name;
  final String ownerId;
  final String? description;

  /// The Multiavatar seed for the group's identicon, so a group has a stable
  /// face of its own (distinct from any member's).
  final String avatarId;

  /// The revocable join code behind the group's invite link, if the row
  /// carries it (only members can read a group, so this is member-visible).
  final String? inviteCode;

  /// Whether redeeming [inviteCode] puts the joiner in a pending state that an
  /// admin must approve.
  final bool inviteRequiresApproval;

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    name: json['name'] as String,
    ownerId: json['owner_id'] as String,
    description: json['description'] as String?,
    avatarId: json['avatar_id'] as String? ?? 'default',
    inviteCode: json['invite_code'] as String?,
    inviteRequiresApproval: json['invite_requires_approval'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner_id': ownerId,
    'description': description,
    'avatar_id': avatarId,
    'invite_code': inviteCode,
    'invite_requires_approval': inviteRequiresApproval,
  };
}

/// The three membership roles a group member can hold. `owner` is unique and
/// cannot be changed without transferring ownership.
enum GroupRole { owner, admin, member }

GroupRole groupRoleFromString(String? value) => switch (value) {
  'owner' => GroupRole.owner,
  'admin' => GroupRole.admin,
  _ => GroupRole.member,
};

extension GroupRoleLabel on GroupRole {
  String get label => switch (this) {
    GroupRole.owner => 'Owner',
    GroupRole.admin => 'Admin',
    GroupRole.member => 'Member',
  };
}

/// What happened when an invite code was redeemed (see `join_group`).
enum JoinGroupResult {
  joined,
  pending,
  alreadyMember,
  alreadyRequested,
  notFound,
}

JoinGroupResult joinGroupResultFromString(String? value) => switch (value) {
  'joined' => JoinGroupResult.joined,
  'pending' => JoinGroupResult.pending,
  'already_member' => JoinGroupResult.alreadyMember,
  'already_requested' => JoinGroupResult.alreadyRequested,
  _ => JoinGroupResult.notFound,
};

/// The public preview of a group behind an invite code, shown before joining
/// (a non-member can't read the group row itself).
class GroupInvitePreview {
  const GroupInvitePreview({
    required this.groupId,
    required this.name,
    this.description,
    this.avatarId = 'default',
    this.memberCount = 0,
    this.requiresApproval = false,
    this.membership = 'none',
  });

  final String groupId;
  final String name;
  final String? description;
  final String avatarId;
  final int memberCount;
  final bool requiresApproval;

  /// `none` | `pending` | `member`.
  final String membership;

  factory GroupInvitePreview.fromJson(Map<String, dynamic> json) =>
      GroupInvitePreview(
        groupId: json['group_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        avatarId: json['avatar_id'] as String? ?? 'default',
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        requiresApproval: json['requires_approval'] as bool? ?? false,
        membership: json['membership'] as String? ?? 'none',
      );
}
