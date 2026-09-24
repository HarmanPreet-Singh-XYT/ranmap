import '../../core/constants/avatars.dart';

/// Columns of `public.profiles` that are readable by every authenticated user.
/// `phone_number` and `socials` are deliberately excluded (RLS column grants
/// in 0002_rls_hardening.sql) and must be fetched only by their owner.
const kProfilePublicColumns =
    'id, username, display_name, avatar_id, vehicle_type';

class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarId = 'default',
    this.vehicleType = kDefaultVehicleType,
    this.phoneNumber,
    this.socials = const {},
  });

  final String id;
  final String username;
  final String? displayName;
  final String avatarId;
  final String vehicleType;
  final String? phoneNumber;
  final Map<String, String> socials;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarId: json['avatar_id'] as String? ?? 'default',
        vehicleType: json['vehicle_type'] as String? ?? kDefaultVehicleType,
        phoneNumber: json['phone_number'] as String?,
        socials: (json['socials'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_id': avatarId,
        'vehicle_type': vehicleType,
        'phone_number': phoneNumber,
        'socials': socials,
      };

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarId,
    String? vehicleType,
    String? phoneNumber,
    Map<String, String>? socials,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarId: avatarId ?? this.avatarId,
      vehicleType: vehicleType ?? this.vehicleType,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      socials: socials ?? this.socials,
    );
  }
}
