import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// The highlighted road for a trip's route or a directions preview, drawn like
/// Google Maps: a bold coloured line with a white casing, and any alternative
/// routes underneath in a muted colour.
///
/// Drawn as our own GeoJSON source + line layers (rather than a polyline
/// annotation manager) so the layers can be placed in a Mapbox Standard slot —
/// a slot-less layer ends up beneath the Standard basemap and is invisible.
class RouteLines {
  static const _sourceId = 'ranmap-route-src';
  static const _altLayerId = 'ranmap-route-alt';
  static const _casingLayerId = 'ranmap-route-casing';
  static const _mainLayerId = 'ranmap-route-main';
  static const _labelLayerId = 'ranmap-route-labels';

  bool _added = false;
  bool _syncing = false;
  bool _rerun = false;
  String? _lastKey;
  _Pending? _pending;

  /// Forgets what's on the map — call when the style is reloaded, which drops
  /// every source and layer added here.
  void reset() {
    _added = false;
    _lastKey = null;
  }

  /// Draws [main] highlighted and [alternatives] muted; an empty [main] clears
  /// the map. [slot] is a Standard slot (`top`), or null for classic styles.
  Future<void> sync(
    MapboxMap map, {
    required List<Position> main,
    List<List<Position>> alternatives = const [],
    String? mainLabel,
    List<String> altLabels = const [],
    required int mainColorArgb,
    required int casingColorArgb,
    required int altColorArgb,
    String? slot,
  }) async {
    // Cheap identity for "same route drawn": size + endpoints + a midpoint.
    String sig(List<Position> p) => p.isEmpty
        ? '-'
        : '${p.length}/${p.first.lat},${p.first.lng}/${p[p.length ~/ 2].lat}/${p.last.lat},${p.last.lng}';
    final key =
        '${sig(main)}|${alternatives.map(sig).join(';')}|$mainLabel|${altLabels.join(',')}|$mainColorArgb|$slot';
    if (_added && key == _lastKey) return;

    _pending = _Pending(
      main,
      alternatives,
      mainLabel,
      altLabels,
      mainColorArgb,
      casingColorArgb,
      altColorArgb,
      slot,
      key,
    );
    if (_syncing) {
      _rerun = true;
      return;
    }
    _syncing = true;
    try {
      final job = _pending!;
      await _apply(map, job);
      _lastKey = job.key;
    } catch (e) {
      // Decorative overlay: never take the map down, but say why in debug.
      debugPrint('RouteLines: sync failed: $e');
    } finally {
      _syncing = false;
    }
    if (_rerun) {
      _rerun = false;
      final job = _pending!;
      await sync(
        map,
        main: job.main,
        alternatives: job.alternatives,
        mainLabel: job.mainLabel,
        altLabels: job.altLabels,
        mainColorArgb: job.mainColorArgb,
        casingColorArgb: job.casingColorArgb,
        altColorArgb: job.altColorArgb,
        slot: job.slot,
      );
    }
  }

  Future<void> _apply(MapboxMap map, _Pending job) async {
    final data = _featureCollection(
      job.main,
      job.alternatives,
      job.mainLabel,
      job.altLabels,
    );
    // A style reload silently drops our source; notice and re-add.
    if (_added && !await map.style.styleSourceExists(_sourceId)) {
      _added = false;
    }
    if (_added && job.key != _lastKey && _colorsOrSlotChanged(job)) {
      await _remove(map);
      _added = false;
    }
    if (!_added) {
      await _remove(map);
      await map.style.addSource(GeoJsonSource(id: _sourceId, data: data));
      // Bottom to top: alternatives, white casing, then the main line.
      await map.style.addLayer(
        LineLayer(
          id: _altLayerId,
          sourceId: _sourceId,
          slot: job.slot,
          filter: [
            '==',
            ['get', 'kind'],
            'alt',
          ],
          lineColor: job.altColorArgb,
          lineWidth: 5,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineEmissiveStrength: 1.0,
        ),
      );
      await map.style.addLayer(
        LineLayer(
          id: _casingLayerId,
          sourceId: _sourceId,
          slot: job.slot,
          filter: [
            '==',
            ['get', 'kind'],
            'main',
          ],
          lineColor: job.casingColorArgb,
          lineWidth: 10,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineEmissiveStrength: 1.0,
        ),
      );
      await map.style.addLayer(
        LineLayer(
          id: _mainLayerId,
          sourceId: _sourceId,
          slot: job.slot,
          filter: [
            '==',
            ['get', 'kind'],
            'main',
          ],
          lineColor: job.mainColorArgb,
          lineWidth: 6,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineEmissiveStrength: 1.0,
        ),
      );
      // Time bubbles at the middle of each route, like Google Maps.
      await map.style.addLayer(
        SymbolLayer(
          id: _labelLayerId,
          sourceId: _sourceId,
          slot: job.slot,
          filter: [
            'in',
            ['get', 'kind'],
            [
              'literal',
              ['label-main', 'label-alt'],
            ],
          ],
          textFieldExpression: ['get', 'text'],
          textFont: ['DIN Pro Bold', 'Arial Unicode MS Bold'],
          textSize: 13,
          textColorExpression: [
            'case',
            [
              '==',
              ['get', 'kind'],
              'label-main',
            ],
            _rgba(job.mainColorArgb),
            'rgba(90, 96, 105, 1)',
          ],
          textHaloColor: 0xFFFFFFFF,
          textHaloWidth: 3,
          textAllowOverlap: true,
          symbolSortKeyExpression: [
            'case',
            [
              '==',
              ['get', 'kind'],
              'label-main',
            ],
            1,
            0,
          ],
          textEmissiveStrength: 1.0,
        ),
      );
      _added = true;
      _appliedStyle = (job.mainColorArgb, job.slot);
    } else {
      await map.style.setStyleSourceProperty(_sourceId, 'data', data);
    }
  }

  (int, String?)? _appliedStyle;

  bool _colorsOrSlotChanged(_Pending job) =>
      _appliedStyle != (job.mainColorArgb, job.slot);

  Future<void> _remove(MapboxMap map) async {
    for (final id in [
      _labelLayerId,
      _mainLayerId,
      _casingLayerId,
      _altLayerId,
    ]) {
      if (await map.style.styleLayerExists(id)) {
        await map.style.removeStyleLayer(id);
      }
    }
    if (await map.style.styleSourceExists(_sourceId)) {
      await map.style.removeStyleSource(_sourceId);
    }
  }

  static String _rgba(int argb) =>
      'rgba(${(argb >> 16) & 0xFF}, ${(argb >> 8) & 0xFF}, ${argb & 0xFF}, 1)';

  static String _featureCollection(
    List<Position> main,
    List<List<Position>> alternatives,
    String? mainLabel,
    List<String> altLabels,
  ) {
    Map<String, Object?> line(List<Position> points, String kind) => {
      'type': 'Feature',
      'properties': {'kind': kind},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final p in points) [p.lng, p.lat],
        ],
      },
    };
    Map<String, Object?> label(
      List<Position> points,
      String text,
      String kind,
    ) {
      final mid = points[points.length ~/ 2];
      return {
        'type': 'Feature',
        'properties': {'kind': kind, 'text': text},
        'geometry': {
          'type': 'Point',
          'coordinates': [mid.lng, mid.lat],
        },
      };
    }

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final alt in alternatives)
          if (alt.length >= 2) line(alt, 'alt'),
        if (main.length >= 2) line(main, 'main'),
        for (final (i, alt) in alternatives.indexed)
          if (alt.length >= 2 && i < altLabels.length)
            label(alt, altLabels[i], 'label-alt'),
        if (main.length >= 2 && mainLabel != null)
          label(main, mainLabel, 'label-main'),
      ],
    });
  }
}

class _Pending {
  _Pending(
    this.main,
    this.alternatives,
    this.mainLabel,
    this.altLabels,
    this.mainColorArgb,
    this.casingColorArgb,
    this.altColorArgb,
    this.slot,
    this.key,
  );

  final List<Position> main;
  final List<List<Position>> alternatives;
  final String? mainLabel;
  final List<String> altLabels;
  final int mainColorArgb;
  final int casingColorArgb;
  final int altColorArgb;
  final String? slot;
  final String key;
}
