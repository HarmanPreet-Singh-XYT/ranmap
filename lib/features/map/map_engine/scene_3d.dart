import 'dart:convert';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Applies the 3D scene to a freshly-loaded style.
///
/// Two independent pieces, because they work in different ways:
///
/// * **Buildings / trees / landmarks / lighting** are part of Mapbox Standard's
///   built-in 3D environment, enabled through the style-import configuration
///   API (`show3dBuildings`, `lightPreset`, …). Classic styles have no
///   `basemap` import, so those calls no-op there.
/// * **Terrain** is added explicitly from Mapbox's Terrain-RGB DEM tileset, so
///   elevation works on every basemap — including the classic ones — and can be
///   toggled independently of the basemap.
abstract final class Scene3D {
  const Scene3D._();

  /// The Mapbox Standard style import that 3D config is applied to.
  static const basemapImportId = 'basemap';

  static const _terrainSourceId = 'ranmap-terrain';
  static const _demTilesetUrl = 'mapbox://mapbox.mapbox-terrain-dem-v1';

  /// Hills read clearly at trip zoom without turning mountains cartoonish.
  static const _terrainExaggeration = 1.35;

  /// Toggles Mapbox Standard's 3D environment and applies a time-of-day
  /// lighting preset. Safe on classic styles (no-op).
  static Future<void> applyStandard3d(
    MapboxMap map, {
    required bool buildings,
    required String lightPreset,
  }) async {
    Future<void> config(String name, Object value) async {
      try {
        await map.style.setStyleImportConfigProperty(
          basemapImportId,
          name,
          value,
        );
      } catch (_) {
        // Not a Standard style (e.g. Outdoors): no `basemap` import to configure.
      }
    }

    await config('show3dBuildings', buildings);
    await config('show3dObjects', buildings);
    await config('show3dTrees', buildings);
    await config('show3dLandmarks', buildings);
    await config('show3dFacades', buildings);
    await config('lightPreset', lightPreset);
  }

  /// Enables or disables 3D terrain. Idempotent — called on every style load.
  static Future<void> setTerrain(MapboxMap map, bool enabled) async {
    try {
      if (enabled) {
        if (!await map.style.styleSourceExists(_terrainSourceId)) {
          await map.style.addSource(
            RasterDemSource(
              id: _terrainSourceId,
              url: _demTilesetUrl,
              tileSize: 512,
            ),
          );
        }
        await map.style.setStyleTerrain(
          jsonEncode({
            'source': _terrainSourceId,
            'exaggeration': _terrainExaggeration,
          }),
        );
      } else {
        // A null terrain source flattens the scene back to 2D.
        await map.style.setStyleTerrain(jsonEncode({'source': null}));
      }
    } catch (_) {
      // Terrain is decorative — never let it take the map down with it.
    }
  }

  /// A Mapbox Standard light preset matched to the user's local time, so the
  /// 3D scene roughly agrees with the world outside the phone.
  static String lightPresetFor(DateTime now) {
    final hour = now.hour;
    if (hour < 6 || hour >= 20) return 'night';
    if (hour < 8) return 'dawn';
    if (hour >= 18) return 'dusk';
    return 'day';
  }

  /// Applies the full scene for [styleUri]'s basemap.
  static Future<void> apply(
    MapboxMap map, {
    required bool buildings,
    required bool terrain,
  }) async {
    await applyStandard3d(
      map,
      buildings: buildings,
      lightPreset: lightPresetFor(DateTime.now()),
    );
    await setTerrain(map, terrain);
  }
}
