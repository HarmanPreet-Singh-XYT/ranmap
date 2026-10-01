import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/brand_palette.dart';
import '../../../core/theme/brand_typography.dart';
import '../../../data/models/route_option.dart';
import 'nav_engine.dart';

/// The glyph for a maneuver, picked from its Mapbox type and modifier.
IconData maneuverIcon(RouteStep step) {
  final m = step.modifier ?? '';
  switch (step.type) {
    case 'arrive':
      return Icons.flag_rounded;
    case 'depart':
      return Icons.navigation_rounded;
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
      return m.contains('left')
          ? Icons.roundabout_left_rounded
          : Icons.roundabout_right_rounded;
    case 'merge':
      return Icons.merge_rounded;
    case 'fork':
      return m.contains('left')
          ? Icons.fork_left_rounded
          : Icons.fork_right_rounded;
    case 'off ramp':
    case 'on ramp':
      return m.contains('left')
          ? Icons.ramp_left_rounded
          : Icons.ramp_right_rounded;
  }
  return switch (m) {
    'left' => Icons.turn_left_rounded,
    'right' => Icons.turn_right_rounded,
    'slight left' => Icons.turn_slight_left_rounded,
    'slight right' => Icons.turn_slight_right_rounded,
    'sharp left' => Icons.turn_sharp_left_rounded,
    'sharp right' => Icons.turn_sharp_right_rounded,
    'uturn' => Icons.u_turn_left_rounded,
    _ => Icons.straight_rounded,
  };
}

/// "350 m" / "1.2 km" (or feet/miles), rounded the way a driver reads it: to
/// 10 m under a kilometre, 50 ft under a tenth of a mile.
String formatManeuverDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.miles) {
    final feet = meters * 3.28084;
    if (feet < 528) return '${(feet / 50).round() * 50} ft';
    return '${(meters / 1609.344).toStringAsFixed(1)} mi';
  }
  if (meters < 1000) return '${((meters / 10).round() * 10).clamp(0, 990)} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _remainingTime(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The big instruction card across the top of the map: how far to the next
/// maneuver, what it is, and a "then…" preview when another follows closely.
class NavBanner extends StatelessWidget {
  const NavBanner({
    super.key,
    required this.progress,
    required this.unit,
    this.rerouting = false,
  });

  final NavProgress progress;
  final DistanceUnit unit;
  final bool rerouting;

  @override
  Widget build(BuildContext context) {
    final step = progress.step;
    final instruction = rerouting
        ? 'Rerouting…'
        : step.type == 'arrive'
        ? (step.instruction.isEmpty
              ? 'Arrive at your destination'
              : step.instruction)
        : step.instruction.isEmpty
        ? 'Continue'
        : step.instruction;
    final bg = BrandColors.primaryContainer;
    final fg = BrandColors.onPrimary;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: BrandShadows.subtle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      rerouting ? Icons.sync_rounded : maneuverIcon(step),
                      key: ValueKey(
                        rerouting ? 'sync' : '${step.type}${step.modifier}',
                      ),
                      size: 52,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!rerouting && step.type != 'arrive')
                          Text(
                            formatManeuverDistance(
                              progress.metersToManeuver,
                              unit,
                            ),
                            style: BrandText.weight(
                              BrandText.titleMd,
                              800,
                            ).copyWith(color: fg, fontSize: 28, height: 1.05),
                          ),
                        Text(
                          instruction,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.bodyMd.copyWith(
                            color: fg.withValues(alpha: 0.95),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!rerouting && progress.thenStep != null)
              Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      'Then',
                      style: BrandText.labelSm.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(maneuverIcon(progress.thenStep!), size: 20, color: fg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        progress.thenStep!.instruction,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.bodySm.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The trip summary under the map while navigating: arrival time, time and
/// distance left, and the controls.
class NavBottomBar extends StatelessWidget {
  const NavBottomBar({
    super.key,
    required this.progress,
    required this.unit,
    required this.following,
    required this.onRecenter,
    required this.onEnd,
  });

  final NavProgress progress;
  final DistanceUnit unit;
  final bool following;
  final VoidCallback onRecenter;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final eta = DateTime.now().add(
      Duration(seconds: progress.remainingSeconds.round()),
    );
    final km = progress.remainingMeters / 1000;
    final distance = unit == DistanceUnit.miles
        ? '${(km * 0.621371).toStringAsFixed(1)} mi'
        : '${km.toStringAsFixed(1)} km';

    Widget stat(String top, String bottom) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          top,
          style: BrandText.weight(
            BrandText.titleSm,
            800,
          ).copyWith(color: BrandColors.textHeadline),
        ),
        Text(
          bottom,
          style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
        ),
      ],
    );

    return Row(
      children: [
        stat(DateFormat.jm().format(eta), 'arrival'),
        const SizedBox(width: 20),
        stat(_remainingTime(progress.remainingSeconds), 'left'),
        const SizedBox(width: 20),
        stat(distance, 'distance'),
        const Spacer(),
        if (!following)
          IconButton(
            tooltip: 'Recenter',
            onPressed: onRecenter,
            icon: Icon(Icons.my_location_rounded, color: BrandColors.primary),
          ),
        FilledButton(
          onPressed: onEnd,
          style: FilledButton.styleFrom(
            backgroundColor: BrandColors.error,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
          child: const Text('End'),
        ),
      ],
    );
  }
}
