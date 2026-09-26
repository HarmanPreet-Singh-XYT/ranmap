import 'package:flutter/material.dart';

import '../../core/constants/avatars.dart';

/// UI helpers for a trip leg's travel mode (`car` | `bike` | `scooter` | `suv` |
/// `other`). Kept in one place so the mode picker and the itinerary's leg pills
/// agree on the glyph and label for each mode.

/// The Material glyph for a travel mode. Unrecognised modes (including `other`)
/// fall back to a neutral route glyph.
IconData vehicleModeIcon(String mode) => switch (mode) {
  'car' => Icons.directions_car,
  'bike' => Icons.two_wheeler,
  'scooter' => Icons.electric_scooter,
  'suv' => Icons.electric_car,
  _ => Icons.route_rounded,
};

/// The display label for a travel mode — the same label the picker uses
/// ([kVehicleOptions]); anything outside that set is title-cased.
String vehicleModeLabel(String mode) {
  for (final option in kVehicleOptions) {
    if (option.id == mode) return option.label;
  }
  return mode.isEmpty ? mode : mode[0].toUpperCase() + mode.substring(1);
}
