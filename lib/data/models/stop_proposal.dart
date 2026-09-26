/// A convoy stop proposal (see 0015_stop_proposals.sql) as returned by the
/// `trip_proposals` RPC: the proposal itself plus its live, row-derived tally.
class StopProposal {
  const StopProposal({
    required this.id,
    required this.name,
    required this.status,
    required this.approvals,
    required this.rejections,
    required this.myVote,
    required this.memberCount,
    this.note,
  });

  final String id;
  final String name;
  final String? note;

  /// open | approved | rejected
  final String status;

  /// How many trip members approved — a real count of `stop_votes` rows.
  final int approvals;

  /// How many trip members rejected.
  final int rejections;

  /// The caller's own vote, or null when they haven't voted yet.
  final bool? myVote;

  /// How many members the majority is measured against.
  final int memberCount;

  bool get isOpen => status == 'open';

  /// Approvals as a 0..1 fraction of the member count (0 when there are no
  /// members to divide by).
  double get approvalFraction =>
      memberCount <= 0 ? 0 : (approvals / memberCount).clamp(0.0, 1.0);

  factory StopProposal.fromJson(Map<String, dynamic> json) => StopProposal(
    id: json['id'] as String,
    name: json['name'] as String,
    note: json['note'] as String?,
    status: json['status'] as String? ?? 'open',
    approvals: (json['approvals'] as num?)?.toInt() ?? 0,
    rejections: (json['rejections'] as num?)?.toInt() ?? 0,
    myVote: json['my_vote'] as bool?,
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
  );
}
