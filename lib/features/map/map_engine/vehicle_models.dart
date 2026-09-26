import 'dart:convert';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'geo.dart';

/// One teammate's live vehicle pose, as rendered by [VehicleModelLayerManager].
class VehiclePose {
  const VehiclePose({
    required this.id,
    required this.vehicleType,
    required this.lat,
    required this.lng,
    this.heading,
  });

  /// Stable identity for diffing (the member's user id).
  final String id;
  final String vehicleType;
  final double lat;
  final double lng;

  /// Degrees clockwise from north; the model is spun to face it.
  final double? heading;

  bool _samePose(VehiclePose other) =>
      vehicleType == other.vehicleType &&
      lat == other.lat &&
      lng == other.lng &&
      heading == other.heading;
}

/// The bundled glTF vehicle models, one per `vehicle_type`.
///
/// Models are authored at real-world scale (meters, glTF Y-up, facing +X), so a
/// single unit scale reads correctly against Mapbox's 3D buildings. Regenerate
/// them with `python3 tool/generate_vehicle_models.py`.
abstract final class VehicleModels {
  const VehicleModels._();

  static const _car = 'asset://assets/models/vehicle_car.glb';
  static const _suv = 'asset://assets/models/vehicle_suv.glb';
  static const _bike = 'asset://assets/models/vehicle_bike.glb';
  static const _scooter = 'asset://assets/models/vehicle_scooter.glb';

  /// The `asset://` URI of the model for a `vehicle_type`, defaulting to the
  /// car for anything unrecognised (matching the profile default).
  static String assetFor(String vehicleType) => switch (vehicleType) {
    'bike' => _bike,
    'scooter' => _scooter,
    'suv' => _suv,
    _ => _car,
  };

  /// The id a [ModelLayer] is given. Mapbox resolves the `asset://` URI to a
  /// platform asset path inside the layer encoder, so no explicit
  /// `addStyleModel` registration is needed.
  static String modelIdFor(String vehicleType) => assetFor(vehicleType);
}

/// Keeps 3D model layers in sync with the teammates on the active trip.
///
/// One GeoJSON source + model layer per *vehicle* rather than one layer per
/// vehicle *type*: `model-rotation` is a fixed 3-vector paint property with no
/// data-driven form for the z-axis, so a per-vehicle layer is what lets each
/// vehicle face its own heading. Teammate counts are small, so the extra layers
/// are cheap. [sync] diffs against the last applied set, making it a no-op on a
/// rebuild where nothing moved.
class VehicleModelLayerManager {
  final Map<String, VehiclePose> _applied = {};
  bool _syncing = false;

  /// Forgets what's on the map — call when the style is reloaded, which drops
  /// every source and layer the manager had added.
  void reset() => _applied.clear();

  Future<void> sync(MapboxMap map, List<VehiclePose> poses) async {
    // Not reentrant: overlapping calls interleave add/remove with `_applied`,
    // which can desync the diff and leave layers missing.
    if (_syncing) return;
    _syncing = true;
    try {
      await _sync(map, poses);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _sync(MapboxMap map, List<VehiclePose> poses) async {
    final wanted = {for (final pose in poses) pose.id: pose};

    for (final id in _applied.keys.toList()) {
      if (!wanted.containsKey(id)) {
        _applied.remove(id);
        await _remove(map, id);
      }
    }

    for (final pose in poses) {
      final previous = _applied[pose.id];
      if (previous == null) {
        _applied[pose.id] = pose;
        await _add(map, pose);
      } else if (previous.vehicleType != pose.vehicleType) {
        await _remove(map, pose.id);
        _applied[pose.id] = pose;
        await _add(map, pose);
      } else if (!previous._samePose(pose)) {
        _applied[pose.id] = pose;
        await _update(map, pose);
      }
    }
  }

  static String _sourceId(String id) => 'ranmap-vehicle-src-$id';
  static String _layerId(String id) => 'ranmap-vehicle-$id';

  Future<void> _add(MapboxMap map, VehiclePose pose) async {
    try {
      await map.style.addSource(
        GeoJsonSource(id: _sourceId(pose.id), data: _featureJson(pose)),
      );
      await map.style.addLayer(
        ModelLayer(
          id: _layerId(pose.id),
          sourceId: _sourceId(pose.id),
          modelId: VehicleModels.modelIdFor(pose.vehicleType),
          modelType: ModelType.COMMON_3D,
          modelScale: const <double?>[1, 1, 1],
          modelRotation: _rotation(pose),
          modelCastShadows: true,
        ),
      );
    } catch (_) {
      // A missing asset or a style that rejects the layer must not take the map
      // down — the rest of the trip UI still works without the 3D layer.
    }
  }

  Future<void> _update(MapboxMap map, VehiclePose pose) async {
    try {
      await map.style.setStyleSourceProperty(
        _sourceId(pose.id),
        'data',
        _featureJson(pose),
      );
      await map.style.setStyleLayerProperty(
        _layerId(pose.id),
        'model-rotation',
        _rotation(pose),
      );
    } catch (_) {}
  }

  Future<void> _remove(MapboxMap map, String id) async {
    try {
      if (await map.style.styleLayerExists(_layerId(id))) {
        await map.style.removeStyleLayer(_layerId(id));
      }
      if (await map.style.styleSourceExists(_sourceId(id))) {
        await map.style.removeStyleSource(_sourceId(id));
      }
    } catch (_) {}
  }

  /// `[x, y, z]` euler angles in degrees. The glTF models are authored facing
  /// +X, and — like the SDK's own default 3D location puck and its model-layer
  /// examples — they need a +90° yaw to line that forward axis up with north
  /// before the vehicle's heading is applied.
  static List<double> _rotation(VehiclePose pose) => [
    0,
    0,
    90 + (pose.heading ?? 0),
  ];

  static String _featureJson(VehiclePose pose) =>
      jsonEncode(Geo.point(pose.lat, pose.lng).toJson());
}
