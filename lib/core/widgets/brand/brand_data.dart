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

/// A labelled share-of-total row: a label + value caption over a proportional
/// brand bar. For a ledger's category split or any "X of Y" breakdown.
class BrandBreakdownRow extends StatelessWidget {
  const BrandBreakdownRow({
    super.key,
    required this.label,
    required this.fraction,
    this.valueLabel,
    this.color,
    this.height = 6,
  });

  final String label;

  /// 0..1; clamped. Usually the row's value over the largest row's value.
  final double fraction;
  final String? valueLabel;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
            ),
          ),
          if (valueLabel != null)
            Text(
              valueLabel!,
              style: BrandText.weight(
                BrandText.labelSm,
                700,
              ).copyWith(color: BrandColors.textHeadline),
            ),
        ],
      ),
      const SizedBox(height: 4),
      BrandProgressBar(value: fraction, color: color, height: height),
    ],
  );
}

/// A bar centred on zero: a negative value fills leftward (what a member owes),
/// a positive one rightward (what they're owed), both scaled to [maxAbs]. For a
/// ledger's "paid vs owed" diverging chart.
class BrandDivergingBar extends StatelessWidget {
  const BrandDivergingBar({
    super.key,
    required this.value,
    required this.maxAbs,
    this.height = 8,
    this.positiveColor,
    this.negativeColor,
  });

  final double value;
  final double maxAbs;
  final double height;
  final Color? positiveColor;
  final Color? negativeColor;

  @override
  Widget build(BuildContext context) {
    final scale = maxAbs <= 0 ? 1.0 : maxAbs;
    final fraction = (value.abs() / scale).clamp(0.0, 1.0);
    final color = value >= 0
        ? (positiveColor ?? BrandColors.primary)
        : (negativeColor ?? BrandColors.error);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          _half(
            fraction: value < 0 ? fraction : 0,
            color: color,
            alignment: Alignment.centerRight,
          ),
          const SizedBox(width: 2),
          _half(
            fraction: value >= 0 ? fraction : 0,
            color: color,
            alignment: Alignment.centerLeft,
          ),
        ],
      ),
    );
  }

  /// One half of the centred bar: a light track with the fill anchored to the
  /// centre ([alignment] is centerRight on the left half, centerLeft on the
  /// right half).
  Widget _half({
    required double fraction,
    required Color color,
    required Alignment alignment,
  }) => Expanded(
    child: ClipRRect(
      borderRadius: BrandRadii.pill,
      child: Container(
        color: BrandColors.surfaceContainerHigh,
        child: Align(
          alignment: alignment,
          child: FractionallySizedBox(
            widthFactor: fraction,
            child: Container(color: color),
          ),
        ),
      ),
    ),
  );
}

/// A compact vertical bar chart: a value caption above each bar and an x-axis
/// label below. For "distance per trip" style series where order matters.
class BrandBarChart extends StatelessWidget {
  const BrandBarChart({
    super.key,
    required this.bars,
    this.height = 132,
    this.color,
    this.valueFormatter,
  });

  final List<({String label, double value})> bars;
  final double height;
  final Color? color;

  /// Formats the value caption above each bar; defaults to a rounded integer.
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxV = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    final barColor = color ?? BrandColors.primaryContainer;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, bar) in bars.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    valueFormatter?.call(bar.value) ??
                        bar.value.round().toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.weight(
                      BrandText.labelSm,
                      700,
                    ).copyWith(color: BrandColors.textHeadline),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      alignment: Alignment.bottomCenter,
                      heightFactor: maxV <= 0
                          ? 0
                          : (bar.value / maxV).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bar.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.bodySm.copyWith(
                      color: BrandColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
