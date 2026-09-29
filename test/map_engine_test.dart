import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/features/map/map_engine/map_engine.dart';

void main() {
  group('Geo', () {
    test('pos() keeps GeoJSON lng,lat order from app lat,lng', () {
      final position = Geo.pos(38.5, -120.2);
      expect(position.lat, 38.5);
      expect(position.lng, -120.2);
    });

    test('point() encodes coordinates as [lng, lat]', () {
      final json = Geo.point(40.7, -120.95).toJson();
      expect(json['type'], 'Point');
      expect(json['coordinates'], [-120.95, 40.7]);
    });
  });

  group('Scene3D.lightPresetFor', () {
    test('maps local hours to Standard light presets', () {
      expect(Scene3D.lightPresetFor(DateTime(2024, 1, 1, 3)), 'night');
      expect(Scene3D.lightPresetFor(DateTime(2024, 1, 1, 7)), 'dawn');
      expect(Scene3D.lightPresetFor(DateTime(2024, 1, 1, 12)), 'day');
      expect(Scene3D.lightPresetFor(DateTime(2024, 1, 1, 19)), 'dusk');
      expect(Scene3D.lightPresetFor(DateTime(2024, 1, 1, 20)), 'night');
    });
  });

  group('RanmapMapStyle', () {
    test('only the Standard styles carry the 3D style import', () {
      expect(RanmapMapStyle.standard.isStandard, isTrue);
      expect(RanmapMapStyle.satellite.isStandard, isTrue);
      expect(RanmapMapStyle.outdoors.isStandard, isFalse);
    });
  });

  group('VehicleModels', () {
    test('maps each vehicle type to its bundled model', () {
      expect(VehicleModels.assetFor('bike'), contains('vehicle_bike.glb'));
      expect(VehicleModels.assetFor('scooter'), contains('vehicle_scooter.glb'));
      expect(VehicleModels.assetFor('suv'), contains('vehicle_suv.glb'));
      expect(VehicleModels.assetFor('car'), contains('vehicle_car.glb'));
    });

    test('falls back to the car model for an unknown type', () {
      expect(VehicleModels.assetFor('hovercraft'), VehicleModels.assetFor('car'));
    });

    test('every model is referenced as a Flutter asset', () {
      for (final type in ['car', 'bike', 'scooter', 'suv']) {
        expect(VehicleModels.modelIdFor(type), startsWith('asset://assets/models/'));
      }
    });
  });
}
