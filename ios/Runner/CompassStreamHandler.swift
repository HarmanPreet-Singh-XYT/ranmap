import CoreLocation
import Flutter
import UIKit

/// Streams the device's compass heading to Dart over the `ranmap/compass`
/// event channel.
///
/// This replaces the `flutter_compass` plugin (which ships only a CocoaPods
/// podspec, no Swift Package) so the iOS build needs no CocoaPods dependency.
final class CompassStreamHandler: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "ranmap/compass",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(CompassStreamHandler())
  }

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.headingFilter = 0.1
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if CLLocationManager.headingAvailable() {
      locationManager.startUpdatingHeading()
    } else {
      // No magnetometer (e.g. some iPads): end the stream so Dart falls back
      // to GPS course for the puck and headlight beam.
      events(FlutterEndOfEventStream)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager.stopUpdatingHeading()
    eventSink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard newHeading.headingAccuracy > 0 else { return }
    // `trueHeading` is -1 until location services are authorised; fall back to
    // the magnetic heading so the beam never snaps to north on a dead reading.
    var heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    // Heading is reported relative to the top of the device; rotate it into the
    // current interface orientation so the beam matches how the map is drawn.
    switch currentInterfaceOrientation() {
    case .portraitUpsideDown: heading += 180
    case .landscapeRight: heading += 90
    case .landscapeLeft: heading -= 90
    default: break
    }
    eventSink?(heading)
  }

  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    true
  }

  private func currentInterfaceOrientation() -> UIInterfaceOrientation {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first?.interfaceOrientation ?? .portrait
  }
}
