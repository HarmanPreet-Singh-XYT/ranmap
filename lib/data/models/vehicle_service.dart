/// Service settings for the user's active vehicle: how often it needs a
/// service, and the odometer reading at the last one. The odometer itself is
/// derived from recorded trip distance.
class VehicleService {
  const VehicleService({this.intervalKm = 10000, this.lastServiceKm = 0});

  final double intervalKm;
  final double lastServiceKm;

  factory VehicleService.fromJson(Map<String, dynamic> json) => VehicleService(
    intervalKm: (json['interval_km'] as num?)?.toDouble() ?? 10000,
    lastServiceKm: (json['last_service_km'] as num?)?.toDouble() ?? 0,
  );
}
