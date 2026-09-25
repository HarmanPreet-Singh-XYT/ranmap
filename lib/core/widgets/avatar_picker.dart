import 'package:flutter/material.dart';

import '../theme/nav_palette.dart';
import 'avatar_view.dart';

/// A wrap of selectable Multiavatar candidates, with an optional "shuffle" tile
/// that rerolls the set — the user keeps a random avatar by default and can
/// pick a different one at any time.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({
    super.key,
    required this.candidates,
    required this.selected,
    required this.onSelect,
    this.onShuffle,
    this.size = 64,
  });

  final List<String> candidates;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback? onShuffle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final seed in candidates)
          Semantics(
            selected: seed == selected,
            button: true,
            label: 'Avatar option',
            child: GestureDetector(
              onTap: () => onSelect(seed),
              child: AvatarView(seed: seed, size: size, selected: seed == selected),
            ),
          ),
        if (onShuffle != null)
          Semantics(
            button: true,
            label: 'Shuffle avatars',
            child: GestureDetector(
              onTap: onShuffle,
              child: Container(
                height: size,
                width: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  border: Border.all(color: c.border, width: 1.5),
                ),
                child: Icon(Icons.shuffle_rounded, color: c.activeRoute),
              ),
            ),
          ),
      ],
    );
  }
}
