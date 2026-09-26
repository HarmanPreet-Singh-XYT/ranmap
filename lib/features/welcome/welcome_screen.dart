import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../../core/providers/app_prefs_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_icons.dart';
import '../../core/widgets/brand/brand_pod.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_step_indicator.dart';
import '../../core/widgets/brand/brand_tag.dart';
import '../auth/social_auth.dart';

/// The v2 intro screen, shown after the v1 feature tour hands off. Its options
/// (email / Google / Apple) each route into the chosen auth flow. The
/// signed-out landing is gated on [AppPrefs.introV1Seen] (the tour), so once
/// that's walked a relaunch resumes here; `introV2Seen` is only a progress flag.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _leaving = false;

  /// Marks the welcome as seen and opens the chosen auth screen.
  ///
  /// Pushes (not `go`) so the welcome stays on the stack — the auth screens'
  /// back returns here. The `_leaving` guard is cleared once that route pops,
  /// so the buttons work again on return.
  Future<void> _leave(String location) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await ref.read(appPrefsProvider).markIntroV2Seen();
    if (!mounted) return;
    await context.push(location);
    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                const SizedBox(height: BrandSpace.sm),
                const BrandDots(count: 3, index: 0),
                const SizedBox(height: BrandSpace.md),
                const _BentoCollage()
                    .animate()
                    .fadeIn(duration: 480.ms, curve: Curves.easeOut)
                    .scale(
                      begin: const Offset(0.96, 0.96),
                      end: const Offset(1, 1),
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: BrandSpace.xl),
                const _ValueProp()
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 420.ms)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: BrandSpace.lg),
                _Actions(onStart: () => _leave('/sign-up'), onSocial: _social)
                    .animate()
                    .fadeIn(delay: 220.ms, duration: 420.ms)
                    .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: BrandSpace.md),
                _Footer(onLogIn: () => _leave('/sign-in')),
                const SizedBox(height: BrandSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the provider's OAuth screen. We mark the intro seen up front so the
  /// welcome isn't re-gated when the browser round-trips back into the app.
  Future<void> _social(OAuthProvider provider) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await ref.read(appPrefsProvider).markIntroV2Seen();
    try {
      final launched = await signInWithProvider(provider);
      if (!launched && mounted) {
        showAppToast(context, 'Could not open the sign-in page');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }
}

/// The 2×2 bento cluster: two photo pods and two pastel illustration pods.
class _BentoCollage extends StatelessWidget {
  const _BentoCollage();

  // Bundled copies of the design previews, so the hero renders offline.
  static const _topLeftPhoto = 'assets/images/onboarding/welcome_crew.jpg';
  static const _bottomRightPhoto = 'assets/images/onboarding/welcome_route.jpg';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _PhotoPod(asset: _topLeftPhoto)),
                      const SizedBox(width: BrandSpace.gutterSm),
                      Expanded(
                        child: BrandPod(
                          color: BrandColors.accentPeach,
                          child: _IllustrationPod(
                            icon: Icons.directions_car_rounded,
                            iconColor: BrandColors.tertiary,
                            label: 'Convoy',
                            dotColor: BrandColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BrandSpace.gutterSm),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: BrandPod(
                          color: BrandColors.accentMint,
                          child: _IllustrationPod(
                            icon: Icons.cell_tower_rounded,
                            iconColor: BrandColors.primary,
                            label: 'Live Audio',
                          ),
                        ),
                      ),
                      const SizedBox(width: BrandSpace.gutterSm),
                      Expanded(
                        child: _PhotoPod(
                          asset: _bottomRightPhoto,
                          badge: 'Route 1',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pastel pod: a frosted circular icon badge over a small dot + label.
class _IllustrationPod extends StatelessWidget {
  const _IllustrationPod({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.dotColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      height: 6,
      width: 6,
      decoration: BoxDecoration(
        color: dotColor ?? BrandColors.primaryContainer,
        shape: BoxShape.circle,
      ),
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        BrandIconBadge(
          icon: icon,
          iconColor: iconColor,
          size: 54,
          iconSize: 28,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.labelSm.copyWith(
                  color: BrandColors.textHeadline,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A photo pod with a rounded clip, drawn over a painted gradient so the tile
/// still reads if the asset is somehow missing.
class _PhotoPod extends StatelessWidget {
  const _PhotoPod({required this.asset, this.badge});

  final String asset;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BrandRadii.podRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandColors.secondaryContainer, BrandColors.accentSky],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            if (badge != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.surface.withValues(alpha: 0.85),
                    borderRadius: BrandRadii.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.near_me_rounded,
                        size: 13,
                        color: BrandColors.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        badge!,
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.textHeadline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ValueProp extends StatelessWidget {
  const _ValueProp();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          const BrandTag(
            icon: Icons.satellite_alt_rounded,
            label: 'Real-Time Convoy Navigation',
          ),
          const SizedBox(height: 12),
          Text(
            'Drive Together,\nStay Connected',
            textAlign: TextAlign.center,
            style: BrandText.displayLgMobile.copyWith(
              color: BrandColors.textHeadline,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Live 3D location, convoy voice chat, and shared road-trip pitstops for every adventure.',
              textAlign: TextAlign.center,
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onStart, required this.onSocial});

  final VoidCallback onStart;
  final ValueChanged<OAuthProvider> onSocial;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BrandPrimaryButton(label: 'Get Started', onPressed: onStart),
        const SizedBox(height: BrandSpace.gutterSm),
        BrandSecondaryButton(
          label: 'Continue with Google',
          leading: const GoogleGlyph(),
          onPressed: () => onSocial(OAuthProvider.google),
        ),
        const SizedBox(height: BrandSpace.gutterSm),
        BrandSecondaryButton(
          label: 'Continue with Apple',
          leading: const AppleGlyph(),
          onPressed: () => onSocial(OAuthProvider.apple),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onLogIn});

  final VoidCallback onLogIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              'Already have a RanMap account?',
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
            GestureDetector(
              onTap: onLogIn,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Log in',
                style: BrandText.weight(
                  BrandText.labelMd,
                  700,
                ).copyWith(color: BrandColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'By continuing you agree to our Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
          ),
        ),
      ],
    );
  }
}
