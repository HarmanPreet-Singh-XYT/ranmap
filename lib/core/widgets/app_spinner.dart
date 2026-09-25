import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// A ForUI circular spinner, optionally recolored (e.g. white inside a filled
/// button).
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.color, this.size = FCircularProgressSizeVariant.sm});

  final Color? color;
  final FCircularProgressSizeVariant size;

  @override
  Widget build(BuildContext context) => FCircularProgress(
        size: size,
        style: color == null
            ? const FCircularProgressStyleDelta.context()
            : FCircularProgressStyleDelta.delta(iconStyle: IconThemeDataDelta.delta(color: color)),
      );
}
