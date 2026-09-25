import 'dart:math';

import 'env.dart';

/// Avatars are Multiavatar identicons: any string is a valid seed, and it maps
/// deterministically to one of ~12.2 billion unique avatars. We store the seed
/// in `profiles.avatar_id`, so a user's avatar is stable across devices.
///
/// Legacy values (`'default'`, or the old animal ids) are still valid seeds, so
/// no data migration is needed — they simply render as their deterministic
/// avatar.
const String kDefaultAvatarSeed = 'default';

/// A user-uploaded photo is stored as `custom:<storage path>`, so the same
/// `avatar_id` column carries both kinds. Anything without this prefix is a
/// Multiavatar seed, which keeps every pre-existing row working.
const String kCustomAvatarPrefix = 'custom:';

/// Whether [avatarId] refers to an uploaded photo rather than a Multiavatar.
bool isCustomAvatar(String avatarId) => avatarId.startsWith(kCustomAvatarPrefix);

/// Builds an `avatar_id` for an uploaded photo at [storagePath] in the
/// (public) `avatars` bucket.
String customAvatarId(String storagePath) => '$kCustomAvatarPrefix$storagePath';

/// The storage path inside the `avatars` bucket for a custom [avatarId].
String customAvatarPath(String avatarId) =>
    avatarId.substring(kCustomAvatarPrefix.length);

/// The public URL for an uploaded avatar. The `avatars` bucket is public (see
/// 0001_init.sql), so no signed URL round-trip is needed to render it.
String customAvatarUrl(String storagePath) {
  final base = Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base/storage/v1/object/public/avatars/$storagePath';
}

final Random _avatarRandom = Random();

/// A random, DB-safe avatar seed (12 hex chars).
String randomAvatarSeed() {
  final buffer = StringBuffer();
  for (var i = 0; i < 12; i++) {
    buffer.write(_avatarRandom.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}

/// A set of distinct candidate seeds for the picker. Always contains [include]
/// (the current pick) so the selected avatar is visible in the grid.
///
/// [include] is ignored when it's an uploaded photo (there's no seed to show).
List<String> avatarSeedCandidates({int count = 12, String? include}) {
  final seeds = <String>{
    if (include != null && include.isNotEmpty && !isCustomAvatar(include)) include,
  };
  while (seeds.length < count) {
    seeds.add(randomAvatarSeed());
  }
  return seeds.toList();
}

/// Vehicle types. On the map each one is rendered as a bundled 3D model (see
/// `features/map/map_engine/vehicle_models.dart`), generated rather than loaded
/// from a hand-authored model image set.
class VehicleOption {
  const VehicleOption(this.id, this.label);

  final String id;
  final String label;
}

const List<VehicleOption> kVehicleOptions = [
  VehicleOption('car', 'Car'),
  VehicleOption('bike', 'Bike'),
  VehicleOption('scooter', 'Scooter'),
  VehicleOption('suv', 'SUV'),
];

/// Vehicle assumed when a profile has none set. Mirrors the `vehicle_type`
/// column default in the migrations, so a locally-built profile matches one the
/// database would build.
const String kDefaultVehicleType = 'car';
