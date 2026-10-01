/// One recipient a pinned photo is shared with. Exactly one of [groupId] /
/// [userId] is set — `map_post_shares` has two nullable target columns and no
/// primary key (see `0001_init.sql` / `0008_hardening_followups.sql`).
class MapPostShare {
  const MapPostShare({
    required this.postId,
    this.groupId,
    this.userId,
    this.groupName,
    this.username,
  });

  final String postId;
  final String? groupId;
  final String? userId;
  final String? groupName;
  final String? username;

  bool get isGroup => groupId != null;

  /// A human label for the recipient — the group name, or `@username`.
  String get label => isGroup ? (groupName ?? 'Group') : '@${username ?? 'member'}';
}
