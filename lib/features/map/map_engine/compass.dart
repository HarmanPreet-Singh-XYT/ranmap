import 'package:flutter/services.dart';

/// Device compass headings, in degrees (0 = north), from the native
/// `ranmap/compass` event channel — implemented in
/// `ios/Runner/CompassStreamHandler.swift` and
/// `android/.../com/ranmap/app/CompassStreamHandler.kt`.
///
/// Replaces the `flutter_compass` plugin, which ships no Swift Package and so
/// forced a CocoaPods dependency.
class RanmapCompass {
  RanmapCompass._();

  static const EventChannel _channel = EventChannel('ranmap/compass');

  /// Emits the device heading in degrees. Completes (no events) on devices
  /// with no magnetometer, so callers fall back to GPS course.
  static Stream<double> get headings =>
      _channel.receiveBroadcastStream().map((dynamic heading) => (heading as num).toDouble());
}
