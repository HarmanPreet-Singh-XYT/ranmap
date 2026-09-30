import 'trip.dart';

class MapPost {
  final String id;
  final String? tripId;
  final String userId;
  final double lat;
  final double lng;
  final String storagePath;
  final String? caption;
  final String visibility; // private | group | public
  final DateTime createdAt;
  final String? posterUsername;

  const MapPost({
    required this.id,
    this.tripId,
    required this.userId,
    required this.lat,
    required this.lng,
    required this.storagePath,
    this.caption,
    required this.visibility,
    required this.createdAt,
    this.posterUsername,
  });

  factory MapPost.fromJson(Map<String, dynamic> json) {
    final point = LatLngPoint.requirePostgrest(json['point']);
    return MapPost(
      id: json['id'] as String,
      tripId: json['trip_id'] as String?,
      userId: json['user_id'] as String,
      lat: point.lat,
      lng: point.lng,
      storagePath: json['storage_path'] as String,
      caption: json['caption'] as String?,
      visibility: json['visibility'] as String? ?? 'group',
      createdAt: DateTime.parse(json['created_at'] as String),
      posterUsername: (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
    );
  }
}
