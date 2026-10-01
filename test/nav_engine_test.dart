import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:ranmap/data/models/route_option.dart';
import 'package:ranmap/features/map/navigation/nav_engine.dart';

const _lat0 = 45.0;
const _lng0 = -75.0;
final _mPerDegLat = 111320.0;
final _mPerDegLng = 111320.0 * math.cos(_lat0 * math.pi / 180);

/// A point [east]/[north] metres from the origin.
({double lat, double lng}) _at(double east, double north) => (
  lat: _lat0 + north / _mPerDegLat,
  lng: _lng0 + east / _mPerDegLng,
);

/// East 500 m, then north 500 m (a left turn), a vertex every 25 m.
RouteOption _lRoute({List<RouteStep> steps = const []}) {
  final pts = <Position>[];
  for (var e = 0.0; e <= 500; e += 25) {
    final p = _at(e, 0);
    pts.add(Position(p.lng, p.lat));
  }
  for (var n = 25.0; n <= 500; n += 25) {
    final p = _at(500, n);
    pts.add(Position(p.lng, p.lat));
  }
  return RouteOption(
    summary: 'test',
    distanceMeters: 1000,
    durationSeconds: 100,
    encodedPolyline: '',
    points: pts,
    steps: steps,
  );
}

void main() {
  group('derived turns', () {
    test('finds the left turn at the corner, between depart and arrive', () {
      final engine = NavEngine(_lRoute());
      expect(engine.steps.map((s) => s.type), ['depart', 'turn', 'arrive']);
      expect(engine.steps[1].modifier, 'left');
      expect(engine.steps[1].instruction, 'Turn left');
      expect(engine.steps[0].distanceMeters, closeTo(500, 15));
    });

    test('a straight road yields only depart and arrive', () {
      final pts = [
        for (var e = 0.0; e <= 400; e += 25)
          Position(_at(e, 0).lng, _at(e, 0).lat),
      ];
      final engine = NavEngine(
        RouteOption(
          summary: 's',
          distanceMeters: 400,
          durationSeconds: 40,
          encodedPolyline: '',
          points: pts,
        ),
      );
      expect(engine.steps.map((s) => s.type), ['depart', 'arrive']);
    });
  });

  group('progress', () {
    test('at the start the next maneuver is the corner, 500 m away', () {
      final engine = NavEngine(_lRoute());
      final p = engine.update(_at(0, 0).lat, _at(0, 0).lng);
      expect(p.step.type, 'turn');
      expect(p.metersToManeuver, closeTo(500, 20));
      expect(p.remainingMeters, closeTo(1000, 20));
      expect(p.offRouteMeters, lessThan(2));
      expect(p.arrived, isFalse);
    });

    test('approaching the corner counts down; past it the arrival is next', () {
      final engine = NavEngine(_lRoute());
      var p = engine.update(_at(400, 0).lat, _at(400, 0).lng);
      expect(p.step.type, 'turn');
      expect(p.metersToManeuver, closeTo(100, 20));

      p = engine.update(_at(500, 200).lat, _at(500, 200).lng);
      expect(p.step.type, 'arrive');
      expect(p.metersToManeuver, closeTo(300, 20));
      expect(p.remainingSeconds, closeTo(30, 4));
    });

    test('detects leaving the route', () {
      final engine = NavEngine(_lRoute());
      final p = engine.update(_at(200, -200).lat, _at(200, -200).lng);
      expect(p.offRouteMeters, greaterThan(NavEngine.offRouteThresholdMeters));
    });

    test('arrives at the end of the route', () {
      final engine = NavEngine(_lRoute());
      final p = engine.update(_at(500, 495).lat, _at(500, 495).lng);
      expect(p.arrived, isTrue);
    });

    test('previews the following maneuver only when it is close', () {
      final route = _lRoute(
        steps: [
          const RouteStep(
            instruction: 'Head east',
            type: 'depart',
            distanceMeters: 500,
            durationSeconds: 50,
            lat: _lat0,
            lng: _lng0,
          ),
          RouteStep(
            instruction: 'Turn left onto Oak Avenue',
            type: 'turn',
            modifier: 'left',
            name: 'Oak Avenue',
            distanceMeters: 100,
            durationSeconds: 10,
            lat: _at(500, 0).lat,
            lng: _at(500, 0).lng,
          ),
          RouteStep(
            instruction: 'Turn right onto Pine Road',
            type: 'turn',
            modifier: 'right',
            name: 'Pine Road',
            distanceMeters: 400,
            durationSeconds: 40,
            lat: _at(500, 100).lat,
            lng: _at(500, 100).lng,
          ),
          RouteStep(
            instruction: 'You have arrived',
            type: 'arrive',
            distanceMeters: 0,
            durationSeconds: 0,
            lat: _at(500, 500).lat,
            lng: _at(500, 500).lng,
          ),
        ],
      );
      final engine = NavEngine(route);
      // Uses the supplied steps, not derived ones.
      expect(engine.steps[1].instruction, 'Turn left onto Oak Avenue');
      final p = engine.update(_at(450, 0).lat, _at(450, 0).lng);
      expect(p.step.name, 'Oak Avenue');
      expect(p.thenStep?.name, 'Pine Road');
    });
  });
}
