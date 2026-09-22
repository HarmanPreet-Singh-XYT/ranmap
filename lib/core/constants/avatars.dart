/// Cartoony Apple-style avatar catalog used at registration and profile edit.
/// Rendering is procedural (the option's initial in a colored badge) — there
/// is no bundled avatar image set in this repo.
class AvatarOption {
  const AvatarOption(this.id, this.label);

  final String id;
  final String label;
}

const List<AvatarOption> kAvatarOptions = [
  AvatarOption('fox', 'Fox'),
  AvatarOption('panda', 'Panda'),
  AvatarOption('owl', 'Owl'),
  AvatarOption('otter', 'Otter'),
  AvatarOption('koala', 'Koala'),
  AvatarOption('tiger', 'Tiger'),
  AvatarOption('bear', 'Bear'),
  AvatarOption('rabbit', 'Rabbit'),
];

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
