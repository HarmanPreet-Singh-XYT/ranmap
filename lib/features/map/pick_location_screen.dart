import 'package:flutter/material.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/app_theme.dart';
import 'map_engine/map_engine.dart';

/// Lets the user pick an arbitrary point on the map (rather than defaulting
/// to their current location) by centering a fixed pin and dragging the map
/// underneath it. Returns the picked [Position], or null if cancelled.
class PickLocationScreen extends StatefulWidget {
  const PickLocationScreen({super.key, this.initialCenter, this.title = 'Pick a location'});

  /// Where to open the camera. Null falls back to a wide, pan-able world view
  /// (used when the user's location isn't known yet).
  final Position? initialCenter;
  final String title;

  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  final _mapKey = GlobalKey<RanmapMapViewState>();

  Future<void> _confirm() async {
    final map = _mapKey.currentState?.map;
    if (map == null) return;
    // The pin is fixed at the centre of the viewport, so the picked point is
    // simply wherever the camera is centered now.
    final camera = await map.getCameraState();
    if (!mounted) return;
    Navigator.of(context).pop(camera.center.coordinates);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Use this spot'),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          RanmapMapView(
            key: _mapKey,
            center: widget.initialCenter,
            zoom: widget.initialCenter == null ? kFallbackMapZoom : 15,
            pitch: 0,
            showUserLocation: true,
          ),
          const IgnorePointer(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin, size: 48, color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
