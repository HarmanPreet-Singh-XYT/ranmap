import 'package:flutter/material.dart';

/// Maps a WMO weather code to an icon + short label. Codes come from
/// Open-Meteo; unknown codes fall back to a neutral cloud rather than nothing.
({IconData icon, String label}) weatherVisual(int? code) {
  if (code == null) return (icon: Icons.help_outline_rounded, label: '—');
  if (code == 0) return (icon: Icons.wb_sunny_rounded, label: 'Clear');
  if (code == 1 || code == 2) {
    return (icon: Icons.wb_cloudy_rounded, label: 'Partly cloudy');
  }
  if (code == 3) return (icon: Icons.cloud_rounded, label: 'Cloudy');
  if (code == 45 || code == 48) return (icon: Icons.foggy, label: 'Fog');
  if (code >= 51 && code <= 57) {
    return (icon: Icons.grain_rounded, label: 'Drizzle');
  }
  if (code >= 61 && code <= 67) {
    return (icon: Icons.water_drop_rounded, label: 'Rain');
  }
  if (code >= 71 && code <= 77) {
    return (icon: Icons.ac_unit_rounded, label: 'Snow');
  }
  if (code >= 80 && code <= 82) {
    return (icon: Icons.umbrella_rounded, label: 'Showers');
  }
  if (code >= 95) return (icon: Icons.thunderstorm_rounded, label: 'Storm');
  return (icon: Icons.cloud_outlined, label: 'Cloudy');
}
