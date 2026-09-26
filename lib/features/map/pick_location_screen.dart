import 'package:flutter/material.dart';

import '../../core/constants/defaults.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import 'map_engine/map_engine.dart';

/// Lets the user pick an arbitrary point on the map (rather than defaulting
/// to their current location) by centering a fixed pin and dragging the map
/// underneath it. Returns the picked [Position], or null if cancelled.
class PickLocationScreen extends StatefulWidget {
  const PickLocationScreen({
    super.key,
    this.initialCenter,
    this.title = 'Pick a location',
  });

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
    return BrandScaffold(
      header: BrandHeader(
        title: widget.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      // Full-bleed map: drop the shell's page margin so the camera fills the
      // viewport edge-to-edge.
      padding: EdgeInsets.zero,
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
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_pin,
                size: 48,
                color: BrandColors.primary,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: BrandSpace.lg,
            child: Center(
              child: BrandPrimaryButton(
                label: 'Use this spot',
                expand: false,
                trailingIcon: Icons.check_rounded,
                onPressed: _confirm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
