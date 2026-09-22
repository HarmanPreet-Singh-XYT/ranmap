enum FriendshipStatus { pending, accepted, blocked }

FriendshipStatus _statusFromString(String? value) {
  return FriendshipStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => FriendshipStatus.pending,
  );
}

class Friendship {
  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    this.status = FriendshipStatus.pending,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;

  factory Friendship.fromJson(Map<String, dynamic> json) => Friendship(
        id: json['id'] as String,
        requesterId: json['requester_id'] as String,
        addresseeId: json['addressee_id'] as String,
        status: _statusFromString(json['status'] as String?),
      );
}
