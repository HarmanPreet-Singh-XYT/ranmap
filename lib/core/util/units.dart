import '../providers/settings_provider.dart';

const double _milesPerKm = 0.621371;

/// A distance in the user's preferred unit, e.g. `12.4 km` / `7.7 mi`.
String formatDistance(double km, DistanceUnit unit, {int decimals = 1}) =>
    unit == DistanceUnit.miles
        ? '${(km * _milesPerKm).toStringAsFixed(decimals)} mi'
        : '${km.toStringAsFixed(decimals)} km';

/// A speed in the user's preferred unit, e.g. `80 km/h` / `50 mph`.
String formatSpeed(double kmh, DistanceUnit unit) =>
    unit == DistanceUnit.miles ? '${(kmh * _milesPerKm).round()} mph' : '${kmh.round()} km/h';

/// The distance symbol, for labels like `Fuel cost / km`.
String distanceUnitSymbol(DistanceUnit unit) => unit == DistanceUnit.miles ? 'mi' : 'km';

/// Converts a km value into the display unit, for per-distance maths.
double distanceInUnit(double km, DistanceUnit unit) =>
    unit == DistanceUnit.miles ? km * _milesPerKm : km;

/// A short distance from metres, e.g. `350 m away` / `0.8 mi away`.
String formatShortDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.miles) {
    final miles = meters / 1609.344;
    return miles < 0.1
        ? '${(meters * 3.28084).round()} ft away'
        : '${miles.toStringAsFixed(1)} mi away';
  }
  return meters < 1000 ? '${meters.round()} m away' : '${(meters / 1000).toStringAsFixed(1)} km away';
}

/// A cost expressed per km, converted to the user's unit (e.g. `$/mi`).
double costPerDistance(double costPerKm, DistanceUnit unit) =>
    costPerKm / distanceInUnit(1, unit);
