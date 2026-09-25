import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/nav_palette.dart';
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
    final c = NavColors.of(context);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(widget.title),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
        suffixes: [
          FButton(
            size: .sm,
            onPress: _confirm,
            child: const Text('Use this spot'),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          RanmapMapView(
            key: _mapKey,
            center: widget.initialCenter,
            zoom: widget.initialCenter == null ? kFallbackMapZoom : 15,
            pitch: 0,
            showUserLocation: true,
          ),
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin, size: 48, color: c.activeRoute),
            ),
          ),
        ],
      ),
    );
  }
}
