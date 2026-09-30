import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// A soft "headlight" cone in front of the user's vehicle, showing the
/// direction of travel like Google Maps' heading beam.
///
/// Drawn as a few nested sectors (longer = fainter) in one GeoJSON source and
/// one fill layer, so it fades out along its length. Its length is sized from
/// the camera zoom to stay a roughly constant size on screen. Hidden whenever
/// there is no reliable heading (e.g. standing still).
class HeadlightBeam {
  static const _sourceId = 'ranmap-headlight-src';
  static const _layerId = 'ranmap-headlight';

  /// Beam reach on screen, in logical pixels (kept short: it is a hint, not a spotlight).
  static const _reachPx = 60.0;

  /// How far above sea level the beam floats on Standard-style maps, to clear
  /// building tops (metres; experimental Mapbox `fill-z-offset`).
  static const _liftMeters = 60.0;

  /// Half the cone's opening angle, in degrees.
  static const _halfAngle = 30.0;

  /// (fraction of full length, opacity), longest / faintest first so the
  /// brighter core paints over it.
  static const _rings = [(1.0, 0.18), (0.7, 0.26), (0.4, 0.36)];

  bool _added = false;
  bool _syncing = false;

  /// A sync request that arrived mid-sync; replayed once the current one ends
  /// so the latest position/zoom always wins.
  bool _rerun = false;

  // The last inputs, so a zoom change can redraw at the new size without
  // waiting for the next location fix.
  double? _lat, _lng, _heading;
  int _colorArgb = 0;
  double? _zoom;

  /// Forgets what's on the map — call when the style is reloaded, which drops
  /// every source and layer added here.
  void reset() => _added = false;

  /// Updates the beam. A null [headingDegrees] hides it. [colorArgb] is the
  /// beam's base colour (its opacity comes from the rings). [slot] places the
  /// layer in a Mapbox Standard slot (`top` keeps it above the basemap, where a
  /// slot-less layer ends up hidden); leave null for classic styles.
  Future<void> sync(
    MapboxMap map, {
    required double lat,
    required double lng,
    required double? headingDegrees,
    required int colorArgb,
    String? slot,
  }) async {
    _lat = lat;
    _lng = lng;
    _heading = headingDegrees;
    _colorArgb = colorArgb;
    // Not reentrant: overlapping awaits would interleave add/update.
    if (_syncing) {
      _rerun = true;
      return;
    }
    _syncing = true;
    try {
      final data = await _data(map, lat, lng, headingDegrees);
      // A style reload silently drops our source; notice that here instead of
      // failing an update and only recovering on the next onStyleReady.
      if (_added && !await map.style.styleSourceExists(_sourceId)) {
        _added = false;
      }
      if (!_added) {
        debugPrint('HeadlightBeam: adding layer (heading $headingDegrees)');
        // Clear leftovers from a half-finished earlier add so re-adding can't
        // collide with an existing id.
        if (await map.style.styleLayerExists(_layerId)) {
          await map.style.removeStyleLayer(_layerId);
        }
        if (await map.style.styleSourceExists(_sourceId)) {
          await map.style.removeStyleSource(_sourceId);
        }
        await map.style.addSource(GeoJsonSource(id: _sourceId, data: data));
        await map.style.addLayer(
          FillLayer(
            id: _layerId,
            sourceId: _sourceId,
            slot: slot,
            // Standard's extruded buildings depth-test against a ground-level
            // fill and hide it, so float the beam above most rooftops there.
            fillZOffset: slot == null ? null : _liftMeters,
            fillColor: colorArgb & 0x00FFFFFF | 0xFF000000,
            fillOpacityExpression: ['get', 'o'],
            fillEmissiveStrength: 1.0,
          ),
        );
        _added = true;
      } else {
        await map.style.setStyleSourceProperty(_sourceId, 'data', data);
      }
    } catch (e) {
      // Decorative: a style that rejects the layer must not take the map down,
      // but say why in debug builds so a missing beam is diagnosable.
      debugPrint('HeadlightBeam: sync failed: $e');
    } finally {
      _syncing = false;
    }
    if (_rerun) {
      _rerun = false;
      await sync(
        map,
        lat: _lat!,
        lng: _lng!,
        headingDegrees: _heading,
        colorArgb: _colorArgb,
        slot: slot,
      );
    }
  }

  /// Redraws at the new size when the camera zoom changes. The beam's length is
  /// in metres, so it only stays a constant size on screen if it is rebuilt as
  /// the zoom changes (and once the map settles at its real initial zoom).
  Future<void> onCameraChanged(MapboxMap map, double zoom) async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    if (_zoom != null && (zoom - _zoom!).abs() < 0.05) return;
    await sync(
      map,
      lat: lat,
      lng: lng,
      headingDegrees: _heading,
      colorArgb: _colorArgb,
    );
  }

  Future<String> _data(
    MapboxMap map,
    double lat,
    double lng,
    double? heading,
  ) async {
    final features = <Map<String, Object?>>[];
    if (heading != null && heading.isFinite && heading >= 0) {
      final zoom = (await map.getCameraState()).zoom;
      _zoom = zoom;
      // Mapbox uses 512 px tiles: metres per logical pixel at this latitude.
      final metersPerPx =
          78271.517 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);
      final reach = _reachPx * metersPerPx;
      for (final (fraction, opacity) in _rings) {
        features.add({
          'type': 'Feature',
          'properties': {'o': opacity},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [_sector(lat, lng, heading, reach * fraction)],
          },
        });
      }
    }
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
  }

  /// A pie-slice ring `[lng, lat]` centred on the point, opening toward
  /// [bearing] (degrees clockwise from north). Flat-earth maths is exact
  /// enough at beam scale.
  static List<List<double>> _sector(
    double lat,
    double lng,
    double bearing,
    double radiusMeters,
  ) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = metersPerDegLat * math.cos(lat * math.pi / 180);
    List<double> at(double bearingDeg, double r) {
      final b = bearingDeg * math.pi / 180;
      return [
        lng + r * math.sin(b) / metersPerDegLng,
        lat + r * math.cos(b) / metersPerDegLat,
      ];
    }

    const steps = 12;
    return [
      [lng, lat],
      for (var i = 0; i <= steps; i++)
        at(bearing - _halfAngle + 2 * _halfAngle * i / steps, radiusMeters),
      [lng, lat],
    ];
  }
}
