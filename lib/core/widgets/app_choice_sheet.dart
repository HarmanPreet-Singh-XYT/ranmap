import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/nav_palette.dart';

/// A bottom sheet listing mutually exclusive [options]; returns the chosen
/// value, or null if dismissed. Pass [selected] to mark the current choice
/// (omit it for a plain "choose one" menu with no preselection).
Future<T?> showAppChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label})> options,
  T? selected,
}) {
  return showFSheet<T>(
    context: context,
    side: FLayout.btt,
    builder: (context) {
      final c = NavColors.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FTileGroup(
                children: [
                  for (final option in options)
                    FTile(
                      title: Text(option.label),
                      selected: option.value == selected,
                      onPress: () => Navigator.of(context).pop(option.value),
                      suffix: option.value == selected
                          ? Icon(Icons.check_rounded, color: c.activeRoute)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
