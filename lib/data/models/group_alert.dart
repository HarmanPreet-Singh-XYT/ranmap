/// A convoy alert raised by a group member: an SOS, a rendezvous ("regroup")
/// point, an arrival/departure check-in, or a quick status (wait / stopping /
/// need fuel).
enum GroupAlertKind { sos, regroup, arrived, departed, wait, stopping, fuel }

GroupAlertKind groupAlertKindFromString(String? value) => switch (value) {
  'sos' => GroupAlertKind.sos,
  'regroup' => GroupAlertKind.regroup,
  'arrived' => GroupAlertKind.arrived,
  'wait' => GroupAlertKind.wait,
  'stopping' => GroupAlertKind.stopping,
  'fuel' => GroupAlertKind.fuel,
  _ => GroupAlertKind.departed,
};

extension GroupAlertKindX on GroupAlertKind {
  String get wire => name;

  String get label => switch (this) {
    GroupAlertKind.sos => 'SOS',
    GroupAlertKind.regroup => 'Regroup',
    GroupAlertKind.arrived => 'Arrived',
    GroupAlertKind.departed => 'Departed',
    GroupAlertKind.wait => 'Wait up',
    GroupAlertKind.stopping => 'Stopping',
    GroupAlertKind.fuel => 'Need fuel',
  };
}

/// One member's reach state for a rendezvous alert.
class AlertCheckin {
  const AlertCheckin({required this.userId, this.arrivedAt, this.departedAt});

  final String userId;
  final DateTime? arrivedAt;
  final DateTime? departedAt;

  /// Arrived and not since departed.
  bool get isPresent => arrivedAt != null && departedAt == null;

  factory AlertCheckin.fromJson(Map<String, dynamic> json) => AlertCheckin(
    userId: json['user_id'] as String,
    arrivedAt: json['arrived_at'] != null
        ? DateTime.parse(json['arrived_at'] as String)
        : null,
    departedAt: json['departed_at'] != null
        ? DateTime.parse(json['departed_at'] as String)
        : null,
  );
}

class GroupAlert {
  const GroupAlert({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.kind,
    required this.createdAt,
    this.message,
    this.lat,
    this.lng,
    this.resolvedAt,
    this.creatorUsername,
    this.creatorAvatarId,
    this.checkins = const [],
  });

  final String id;
  final String groupId;
  final String createdBy;
  final GroupAlertKind kind;
  final String? message;
  final double? lat;
  final double? lng;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? creatorUsername;
  final String? creatorAvatarId;
  final List<AlertCheckin> checkins;

  bool get isResolved => resolvedAt != null;
  bool get hasPoint => lat != null && lng != null;

  /// Members currently at the rendezvous.
  int get presentCount => checkins.where((c) => c.isPresent).length;

  factory GroupAlert.fromJson(Map<String, dynamic> json) {
    final point = json['point'] as Map<String, dynamic>?;
    double? lat;
    double? lng;
    if (point != null && point['coordinates'] is List) {
      final coords = point['coordinates'] as List<dynamic>;
      lng = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    }
    final creator = json['creator'] as Map<String, dynamic>?;
    final rawCheckins = json['alert_checkins'] as List<dynamic>? ?? const [];
    return GroupAlert(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String,
      kind: groupAlertKindFromString(json['kind'] as String?),
      message: json['message'] as String?,
      lat: lat,
      lng: lng,
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      creatorUsername: creator?['username'] as String?,
      creatorAvatarId: creator?['avatar_id'] as String?,
      checkins: [
        for (final row in rawCheckins)
          AlertCheckin.fromJson(row as Map<String, dynamic>),
      ],
    );
  }
}
