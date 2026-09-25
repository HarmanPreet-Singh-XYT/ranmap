import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Shows a short toast at the bottom of the screen.
///
/// A thin wrapper over Forui's [showFToast] so call sites don't repeat the
/// alignment/variant boilerplate. Pass [error] for destructive/error messaging.
void showAppToast(BuildContext context, String message, {bool error = false}) {
  showFToast(
    context: context,
    title: Text(message),
    variant: error ? FToastVariant.destructive : FToastVariant.primary,
    alignment: FToastAlignment.bottomCenter,
  );
}
