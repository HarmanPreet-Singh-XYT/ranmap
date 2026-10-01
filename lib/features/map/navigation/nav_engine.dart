import 'dart:math' as math;

import '../../../core/util/geo_distance.dart';
import '../../../data/models/route_option.dart';

/// Where the traveller is on a route and what's coming next.
class NavProgress {
  const NavProgress({
    required this.stepIndex,
    required this.step,
    required this.metersToManeuver,
    required this.thenStep,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.offRouteMeters,
    required this.arrived,
  });

  /// Index (into the engine's steps) of the next maneuver.
  final int stepIndex;

  /// The next maneuver to perform (the last step is the arrival).
  final RouteStep step;
  final double metersToManeuver;

  /// The maneuver after [step], when it follows closely enough to be worth a
  /// "then…" preview; otherwise null.
  final RouteStep? thenStep;
  final double remainingMeters;
  final double remainingSeconds;

  /// Distance from the route line; large values mean the traveller left it.
  final double offRouteMeters;
  final bool arrived;
}

/// Follows a traveller along a [RouteOption]: projects each GPS fix onto the
/// route to find progress, picks the next maneuver, and measures what's left.
///
/// Pure Dart, no plugins — the whole thing is unit-tested against synthetic
/// routes. When the route came back without steps (an older server, or a
/// planning-only route), turns are derived from the polyline's own geometry so
/// the banner still works, just without street names.
class NavEngine {
  NavEngine(RouteOption route)
    : _lats = [for (final p in route.points) p.lat.toDouble()],
      _lngs = [for (final p in route.points) p.lng.toDouble()],
      _totalSeconds = route.durationSeconds.toDouble() {
    _cum = _cumulative();
    totalMeters = _cum.isEmpty ? 0 : _cum.last;
    final raw = route.steps.length >= 2
        ? route.steps
        : deriveSteps(
            route.points.length < 2 ? const [] : _pairs(),
            _cum,
            _totalSeconds,
          );
    steps = raw;
    _stepAt = _projectSteps(raw);
  }

  final List<double> _lats;
  final List<double> _lngs;
  final double _totalSeconds;
  late final List<double> _cum;
  late final double totalMeters;
  late final List<RouteStep> steps;

  /// Distance along the route at which each step's maneuver happens.
  late final List<double> _stepAt;

  /// Last matched segment, so matching stays near the previous fix instead of
  /// jumping to a different part of a looping route.
  int _seg = 0;

  /// Off-route distance beyond which the traveller counts as having left the
  /// route (GPS noise is a few metres; a parallel street is 15–30 m).
  static const double offRouteThresholdMeters = 45;
  static const double arriveWithinMeters = 30;

  List<(double, double)> _pairs() => [
    for (var i = 0; i < _lats.length; i++) (_lats[i], _lngs[i]),
  ];

  List<double> _cumulative() {
    final out = <double>[];
    var d = 0.0;
    for (var i = 0; i < _lats.length; i++) {
      if (i > 0) {
        d += haversineMeters(_lats[i - 1], _lngs[i - 1], _lats[i], _lngs[i]);
      }
      out.add(d);
    }
    return out;
  }

  /// Distance along the route of each step's maneuver, nondecreasing.
  List<double> _projectSteps(List<RouteStep> list) {
    final out = <double>[];
    var from = 0;
    var last = 0.0;
    for (var i = 0; i < list.length; i++) {
      if (i == 0) {
        out.add(0);
        continue;
      }
      if (i == list.length - 1) {
        out.add(totalMeters);
        continue;
      }
      final hit = _project(
        list[i].lat,
        list[i].lng,
        fromSeg: from,
        window: 4000,
      );
      from = hit.seg;
      last = math.max(last, hit.along);
      out.add(last);
    }
    return out;
  }

  /// Projects a point onto the route, searching segments from [fromSeg]
  /// (inclusive) for up to [window] of them; falls back to the whole route.
  ({int seg, double along, double dist}) _project(
    double lat,
    double lng, {
    required int fromSeg,
    int window = 80,
  }) {
    ({int seg, double along, double dist})? best;
    final n = _lats.length - 1;
    if (n < 1) return (seg: 0, along: 0, dist: 0);
    final start = math.max(0, fromSeg);
    final end = math.min(n, start + window);
    for (var i = start; i < end; i++) {
      final hit = _onSegment(i, lat, lng);
      if (best == null || hit.dist < best.dist) best = hit;
    }
    // Nothing near the last position: the traveller may have jumped (GPS fix
    // after a tunnel) — search the entire route before giving up.
    if (best == null || best.dist > 150) {
      for (var i = 0; i < n; i++) {
        final hit = _onSegment(i, lat, lng);
        if (best == null || hit.dist < best.dist) best = hit;
      }
    }
    return best!;
  }

  ({int seg, double along, double dist}) _onSegment(
    int i,
    double lat,
    double lng,
  ) {
    // Local flat projection around the point: accurate to centimetres at the
    // scale of a road segment.
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = metersPerDegLat * math.cos(lat * math.pi / 180);
    final ax = (_lngs[i] - lng) * metersPerDegLng;
    final ay = (_lats[i] - lat) * metersPerDegLat;
    final bx = (_lngs[i + 1] - lng) * metersPerDegLng;
    final by = (_lats[i + 1] - lat) * metersPerDegLat;
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    final t = lenSq == 0 ? 0.0 : ((-ax * dx - ay * dy) / lenSq).clamp(0.0, 1.0);
    final px = ax + t * dx;
    final py = ay + t * dy;
    final segLen = _cum[i + 1] - _cum[i];
    return (
      seg: i,
      along: _cum[i] + t * segLen,
      dist: math.sqrt(px * px + py * py),
    );
  }

  /// Progress for a GPS fix.
  NavProgress update(double lat, double lng) {
    final hit = _project(lat, lng, fromSeg: math.max(0, _seg - 3));
    _seg = hit.seg;
    final along = hit.along;
    final remaining = math.max(0.0, totalMeters - along);

    // Next maneuver: the first step (after the departure) still ahead.
    var idx = steps.length - 1;
    for (var i = 1; i < steps.length; i++) {
      if (_stepAt[i] > along + 3) {
        idx = i;
        break;
      }
    }
    final toManeuver = math.max(0.0, _stepAt[idx] - along);
    RouteStep? then;
    if (idx + 1 < steps.length && _stepAt[idx + 1] - _stepAt[idx] < 250) {
      then = steps[idx + 1];
    }

    final seconds = totalMeters <= 0
        ? 0.0
        : _totalSeconds * (remaining / totalMeters);
    return NavProgress(
      stepIndex: idx,
      step: steps[idx],
      metersToManeuver: toManeuver,
      thenStep: then,
      remainingMeters: remaining,
      remainingSeconds: seconds,
      offRouteMeters: hit.dist,
      arrived: remaining <= arriveWithinMeters && hit.dist < 100,
    );
  }

  /// Turns inferred from the route's shape: a departure, each sharp change of
  /// heading, and the arrival.
  static List<RouteStep> deriveSteps(
    List<(double, double)> points,
    List<double> cum,
    double totalSeconds,
  ) {
    if (points.length < 2) return const [];
    final total = cum.last;
    final secondsPerMeter = total <= 0 ? 0.0 : totalSeconds / total;

    double bearing(int a, int b) {
      final (la, lna) = points[a];
      final (lb, lnb) = points[b];
      final y =
          math.sin((lnb - lna) * math.pi / 180) * math.cos(lb * math.pi / 180);
      final x =
          math.cos(la * math.pi / 180) * math.sin(lb * math.pi / 180) -
          math.sin(la * math.pi / 180) *
              math.cos(lb * math.pi / 180) *
              math.cos((lnb - lna) * math.pi / 180);
      return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    }

    // Index `window` metres behind / ahead of vertex i.
    int back(int i, double meters) {
      var j = i;
      while (j > 0 && cum[i] - cum[j] < meters) {
        j--;
      }
      return j;
    }

    int ahead(int i, double meters) {
      var j = i;
      while (j < points.length - 1 && cum[j] - cum[i] < meters) {
        j++;
      }
      return j;
    }

    final turns = <({int i, double delta})>[];
    for (var i = 1; i < points.length - 1; i++) {
      final a = back(i, 25);
      final b = ahead(i, 25);
      if (a == i || b == i) continue;
      final delta = ((bearing(i, b) - bearing(a, i) + 540) % 360) - 180;
      if (delta.abs() >= 45) turns.add((i: i, delta: delta));
    }
    // A single corner shows up on several consecutive vertices: keep the
    // sharpest of each cluster (vertices within 40 m of each other).
    final kept = <({int i, double delta})>[];
    for (final t in turns) {
      if (kept.isNotEmpty && cum[t.i] - cum[kept.last.i] < 40) {
        if (t.delta.abs() > kept.last.delta.abs()) kept[kept.length - 1] = t;
      } else {
        kept.add(t);
      }
    }

    final out = <RouteStep>[];
    final marks = <double>[0];
    out.add(
      RouteStep(
        instruction: 'Head out',
        type: 'depart',
        distanceMeters: 0,
        durationSeconds: 0,
        lat: points.first.$1,
        lng: points.first.$2,
      ),
    );
    for (final t in kept) {
      final d = t.delta;
      final right = d > 0;
      final abs = d.abs();
      final String modifier;
      final String text;
      if (abs >= 165) {
        modifier = 'uturn';
        text = 'Make a U-turn';
      } else if (abs >= 120) {
        modifier = right ? 'sharp right' : 'sharp left';
        text = 'Take a sharp ${right ? 'right' : 'left'}';
      } else if (abs >= 70) {
        modifier = right ? 'right' : 'left';
        text = 'Turn ${right ? 'right' : 'left'}';
      } else {
        modifier = right ? 'slight right' : 'slight left';
        text = 'Bear ${right ? 'right' : 'left'}';
      }
      out.add(
        RouteStep(
          instruction: text,
          type: 'turn',
          modifier: modifier,
          distanceMeters: 0,
          durationSeconds: 0,
          lat: points[t.i].$1,
          lng: points[t.i].$2,
        ),
      );
      marks.add(cum[t.i]);
    }
    out.add(
      RouteStep(
        instruction: 'You have arrived',
        type: 'arrive',
        distanceMeters: 0,
        durationSeconds: 0,
        lat: points.last.$1,
        lng: points.last.$2,
      ),
    );
    marks.add(total);

    // Fill in each step's length (to the next maneuver) and time.
    return [
      for (var i = 0; i < out.length; i++)
        RouteStep(
          instruction: out[i].instruction,
          type: out[i].type,
          modifier: out[i].modifier,
          name: out[i].name,
          distanceMeters: i + 1 < marks.length ? marks[i + 1] - marks[i] : 0,
          durationSeconds: i + 1 < marks.length
              ? (marks[i + 1] - marks[i]) * secondsPerMeter
              : 0,
          lat: out[i].lat,
          lng: out[i].lng,
        ),
    ];
  }
}
