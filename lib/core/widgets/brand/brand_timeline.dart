import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';

/// Where a timeline entry sits in the journey.
enum BrandTimelineState { done, active, upcoming }

/// A vertical-timeline row: a dotted rail with a state dot on the left and the
/// entry's content on the right. Used for the trip's stop itinerary.
class BrandTimelineRow extends StatelessWidget {
  const BrandTimelineRow({
    super.key,
    required this.child,
    required this.state,
    this.isLast = false,
  });

  final Widget child;
  final BrandTimelineState state;

  /// Omits the connector below the dot for the final entry.
  final bool isLast;

  static const double _railWidth = 26;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(
                state: state,
                isLast: isLast,
                dotCenterY: 22,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Dot(state: state),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : BrandSpace.gutterSm,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final BrandTimelineState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      BrandTimelineState.done => Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: BrandColors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check_rounded,
          size: 13,
          color: BrandColors.onPrimary,
        ),
      ),
      BrandTimelineState.active => Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: BrandColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: BrandColors.primaryContainer, width: 3),
        ),
        child: Center(
          child: Container(
            height: 8,
            width: 8,
            decoration: BoxDecoration(
              color: BrandColors.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      BrandTimelineState.upcoming => Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: BrandColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: BrandColors.outlineVariant, width: 2),
        ),
      ),
    };
  }
}

/// Dashed connector from just under the dot to the bottom of the row.
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.state,
    required this.isLast,
    required this.dotCenterY,
  });

  final BrandTimelineState state;
  final bool isLast;
  final double dotCenterY;

  @override
  void paint(Canvas canvas, Size size) {
    if (isLast) return;
    final paint = Paint()
      ..color = state == BrandTimelineState.done
          ? BrandColors.primaryContainer.withValues(alpha: 0.5)
          : BrandColors.outlineVariant
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    const dash = 4.0;
    const gap = 4.0;
    for (var y = dotCenterY + 12; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + dash).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.isLast != isLast;
}
