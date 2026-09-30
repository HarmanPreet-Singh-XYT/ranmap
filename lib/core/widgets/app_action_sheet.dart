import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../theme/brand_palette.dart';
import '../theme/brand_typography.dart';
import '../theme/nav_palette.dart';
import 'brand/brand_sheet_surface.dart';

/// One entry of a long-press action sheet.
class AppSheetAction {
  const AppSheetAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Tints the row red (delete, leave, remove…).
  final bool destructive;
}

/// Opens a bottom sheet of [actions] for a long-pressed item, with a light
/// haptic so the hold registers. The chosen action runs after the sheet closes.
///
/// Long-press menus replace always-visible icon buttons on list rows: the row
/// stays uncluttered and the same gesture works everywhere in the app.
Future<void> showAppActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<AppSheetAction> actions,
}) async {
  if (actions.isEmpty) return;
  HapticFeedback.mediumImpact();
  final chosen = await showFSheet<AppSheetAction>(
    context: context,
    side: FLayout.btt,
    builder: (sheetContext) {
      final c = NavColors.of(sheetContext);
      return BrandSheetSurface(
        padding: const EdgeInsets.only(top: BrandSpace.md, bottom: 8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.foreground,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.bodySm.copyWith(
                        color: BrandColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FTileGroup(
                children: [
                  for (final action in actions)
                    FTile(
                      prefix: Icon(
                        action.icon,
                        color: action.destructive
                            ? BrandColors.error
                            : c.foreground,
                      ),
                      title: Text(
                        action.label,
                        style: action.destructive
                            ? TextStyle(color: BrandColors.error)
                            : null,
                      ),
                      onPress: () => Navigator.of(sheetContext).pop(action),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  chosen?.onSelected();
}

/// A muted one-liner telling people a list responds to press-and-hold, since a
/// gesture has no visible affordance of its own.
class LongPressHint extends StatelessWidget {
  const LongPressHint({super.key, this.text = 'Press and hold a row for more options.'});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: BrandSpace.md, left: 4, right: 4),
    child: Row(
      children: [
        Icon(Icons.touch_app_outlined, size: 14, color: BrandColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
        ),
      ],
    ),
  );
}
