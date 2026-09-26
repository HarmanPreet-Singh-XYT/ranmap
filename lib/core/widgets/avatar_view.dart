import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:multiavatar_plus/multiavatar_plus.dart';

import '../constants/avatars.dart';
import '../theme/nav_palette.dart';

/// Renders the Multiavatar for [seed] in a circle.
///
/// Multiavatar is an identicon: the same seed always produces the same avatar,
/// so it's stable without storing an image. Generated SVG strings are memoized
/// because avatar grids regenerate on every rebuild.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.seed,
    this.size = 64,
    this.selected = false,
    this.background,
    this.accentColor,
  });

  final String seed;
  final double size;
  final bool selected;
  final Color? background;

  /// Selection ring / glow colour. Defaults to the navigation palette's active
  /// route; brand surfaces pass the grass-green accent.
  final Color? accentColor;

  /// Bounded LRU of generated SVG markup, keyed by seed. Avatar grids shuffle
  /// and reroll repeatedly, so an unbounded map would grow for the whole
  /// process lifetime; this caps it at [_svgCacheMax] entries.
  static const int _svgCacheMax = 256;
  static final Map<String, String> _svgCache = {};

  /// The memoized SVG markup for [seed].
  static String svgFor(String seed) {
    final key = seed.isEmpty ? kDefaultAvatarSeed : seed;
    final cached = _svgCache.remove(key);
    if (cached != null) {
      // Re-insert to mark it most-recently-used.
      _svgCache[key] = cached;
      return cached;
    }
    final svg = multiavatar(key, transparentBackground: true);
    _svgCache[key] = svg;
    if (_svgCache.length > _svgCacheMax) {
      _svgCache.remove(_svgCache.keys.first);
    }
    return svg;
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final accent = accentColor ?? c.activeRoute;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? c.surfaceAlt,
        border: Border.all(
          color: selected ? accent : c.border,
          width: selected ? 3 : 1.5,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.30),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: isCustomAvatar(seed)
          ? Image.network(
              customAvatarUrl(customAvatarPath(seed)),
              fit: BoxFit.cover,
              // A removed/failed photo shouldn't leave a broken tile.
              errorBuilder: (_, _, _) => Icon(Icons.person_rounded, color: c.mutedForeground),
            )
          : SvgPicture.string(
              svgFor(seed),
              fit: BoxFit.cover,
              // The avatar is decorative next to its username; the picker
              // supplies its own semantics.
              excludeFromSemantics: true,
            ),
    );
  }
}
