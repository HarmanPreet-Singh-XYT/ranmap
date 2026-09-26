import 'package:flutter/material.dart';

/// Presentation copy for a vehicle type, shared by onboarding and the profile's
/// Vehicle Garage so the two always agree. The `id` matches
/// `kVVehicleOptions` / `profiles.vehicle_type`.
class VehicleDisplay {
  const VehicleDisplay(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

const Map<String, VehicleDisplay> kVehicleDisplay = {
  'car': VehicleDisplay(
    'Sport Coupe',
    'Agile · Lead Scout',
    Icons.directions_car_rounded,
  ),
  'bike': VehicleDisplay(
    'Adventure Bike',
    'Two-Wheel Navigator',
    Icons.two_wheeler_rounded,
  ),
  'scooter': VehicleDisplay(
    'City Scooter',
    'Urban Scout',
    Icons.electric_scooter_rounded,
  ),
  'suv': VehicleDisplay(
    'Electric SUV',
    'Heavy Cruiser & Cargo',
    Icons.electric_car_rounded,
  ),
};

/// The display copy for [id], falling back to the raw id.
VehicleDisplay vehicleDisplay(String id) =>
    kVehicleDisplay[id] ?? VehicleDisplay(id, id, Icons.directions_car_rounded);
