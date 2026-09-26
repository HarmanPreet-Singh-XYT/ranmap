import 'package:flutter/material.dart';

import '../../theme/brand_palette.dart';
import '../../theme/brand_typography.dart';

/// Lays out [BrandStatTile]s two-per-row with the brand gutters — the 2×2
/// telemetry grids the trip/profile/ledger screens lean on.
class BrandStatGrid extends StatelessWidget {
  const BrandStatGrid({
    super.key,
    required this.tiles,
    this.spacing = BrandSpace.sm,
  });

  final List<Widget> tiles;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final hasSecond = i + 1 < tiles.length;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[i]),
            SizedBox(width: spacing),
            Expanded(child: hasSecond ? tiles[i + 1] : const SizedBox.shrink()),
          ],
        ),
      );
      if (i + 2 < tiles.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}

/// A soft track with a rounded brand fill — quota, budget and progress bars.
class BrandProgressBar extends StatelessWidget {
  const BrandProgressBar({
    super.key,
    required this.value,
    this.color,
    this.track,
    this.height = 8,
  });

  /// 0..1; clamped.
  final double value;
  final Color? color;
  final Color? track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: height,
        decoration: BoxDecoration(
          color: track ?? BrandColors.surfaceContainerHigh,
          borderRadius: BrandRadii.pill,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: constraints.maxWidth * v,
            decoration: BoxDecoration(
              color: color ?? BrandColors.primaryContainer,
              borderRadius: BrandRadii.pill,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small inline area chart (line + faint fill + end dot). Used for the
/// "recent trips / telemetry" sparklines.
class BrandSparkline extends StatelessWidget {
  const BrandSparkline({
    super.key,
    required this.values,
    this.color,
    this.fill,
    this.width = 112,
    this.height = 32,
  });

  final List<double> values;
  final Color? color;
  final Color? fill;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(width: width, height: height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values,
          color ?? BrandColors.primaryContainer,
          fill ?? BrandColors.primaryContainer.withValues(alpha: 0.12),
          BrandColors.primary,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.lineColor, this.fillColor, this.dotColor);

  final List<double> values;
  final Color lineColor;
  final Color fillColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);

    final dx = size.width / (values.length - 1);
    double x(int i) => dx * i;
    double y(double v) =>
        size.height - ((v - minV) / range) * (size.height - 4) - 2;

    final line = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(x(values.length - 1), y(values.last)),
      3,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.dotColor != dotColor;
}

/// A "Recents / telemetry" strip: a label + summary on the left, sparkline on
/// the right. Reused by the profile rollup and the trip stats tab.
class BrandSparklineRow extends StatelessWidget {
  const BrandSparklineRow({
    super.key,
    required this.title,
    required this.caption,
    required this.values,
    this.captionColor,
  });

  final String title;
  final String caption;
  final List<double> values;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.canvas,
        borderRadius: BrandRadii.miniRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BrandText.weight(
                    BrandText.labelSm,
                    700,
                  ).copyWith(color: BrandColors.textHeadline),
                ),
                Text(
                  caption,
                  style: BrandText.bodySm.copyWith(
                    color: captionColor ?? BrandColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BrandSparkline(values: values),
        ],
      ),
    );
  }
}
