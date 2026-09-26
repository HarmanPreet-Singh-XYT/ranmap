import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/avatars.dart';
import '../../core/constants/env.dart';
import '../../core/constants/plan_limits.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/avatar_view.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_tag.dart';
import '../trip/trip_providers.dart';
import 'premium_providers.dart';
import 'premium_purchaser.dart';
import 'revenuecat.dart';

/// Legal links are configured via env (see .env.example); a link is omitted
/// when its URL isn't set, rather than pointing somewhere that may not exist.

/// Opens [url] in the external browser, reporting failure instead of no-opping.
Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (!await canLaunchUrl(uri)) {
    if (context.mounted) {
      showAppToast(context, 'Could not open that link', error: true);
    }
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The full-screen RanMap Pro paywall — shown once after sign-in/sign-up (once
/// onboarding completes) and again every week while the user isn't Pro.
///
/// Distinct from the contextual bottom sheet in `paywall.dart`, which stays
/// tied to a specific in-app feature limit.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  PaywallPlan _plan = PaywallPlan.annual;
  bool _busy = false;
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _purchase() async {
    setState(() => _busy = true);
    try {
      await ref.read(premiumPurchaserProvider).purchase(plan: _plan);
      // A successful purchase flips the plan server-side; refetch it.
      ref.invalidate(entitlementsProvider);
      if (mounted) _close();
    } on PremiumPurchaseCancelled {
      // The user dismissed the store sheet — nothing to show.
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final restored = await ref.read(premiumPurchaserProvider).restore();
      ref.invalidate(entitlementsProvider);
      if (mounted) {
        showAppToast(
          context,
          restored ? 'Purchases restored.' : 'No purchases to restore.',
        );
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageSubscription() async {
    final uri = Uri.parse(
      Theme.of(context).platform == TargetPlatform.iOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );
    if (!await canLaunchUrl(uri)) {
      if (mounted) {
        showAppToast(
          context,
          'Could not open subscription settings',
          error: true,
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // A Pro user has nothing to do here — leave quietly.
    if (ref.watch(isProProvider) && !_closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }

    final offering = ref.watch(paywallOfferingProvider).valueOrNull;
    final annual = offering?.annual;
    final monthly = offering?.monthly;

    // Never fabricate a price or a trial. When billing isn't configured (or a
    // package is missing) show a placeholder rather than the design's copy —
    // advertising a trial the store won't grant is a compliance problem.
    final annualTotal = annual?.storeProduct.priceString ?? '—';
    final annualPerMonth = _perMonth(annual, fallback: '—');
    final monthlyPrice = monthly?.storeProduct.priceString ?? '—';
    final trial = _trialLabel(annual);

    // Offer only what the store actually sells; derive any saving from its own
    // prices rather than asserting one.
    final hasPricing = annual != null || monthly != null;
    final savePercent = _savePercent(annual, monthly);
    final annualIsBest = _annualIsBest(annual, monthly);

    final isAnnual = _plan == PaywallPlan.annual && annual != null;
    final ctaLabel = !hasPricing
        ? 'Purchases unavailable right now'
        : isAnnual
        ? (trial != null
              ? 'Start $trial & Unlock Pro'
              : 'Subscribe & Unlock Pro')
        : 'Unlock Monthly Pass ($monthlyPrice/mo)';

    return BrandScaffold(
      header: _PaywallHeader(onBack: _close),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.sm,
          bottom: BrandSpace.xl,
        ),
        children: [
          const _Hero(),
          const SizedBox(height: BrandSpace.lg),
          const _AmbientTripCard(),
          const SizedBox(height: BrandSpace.lg),
          const _ComparisonTable(),
          const SizedBox(height: BrandSpace.lg),
          _Benefits(),
          const SizedBox(height: BrandSpace.lg),
          if (hasPricing)
            _PlanSelector(
              plan: _plan,
              annualTotal: annualTotal,
              annualPerMonth: annualPerMonth,
              monthlyPrice: monthlyPrice,
              trial: trial,
              showAnnual: annual != null,
              showMonthly: monthly != null,
              savePercent: savePercent,
              annualIsBest: annualIsBest,
              onSelect: (p) => setState(() => _plan = p),
            )
          else
            const _PricingUnavailable(),
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: ctaLabel,
            leadingIcon: Icons.bolt_rounded,
            trailingIcon: null,
            loading: _busy,
            onPressed: hasPricing ? _purchase : null,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 15, color: BrandColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'No commitment. Cancel in App Store settings anytime.',
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.textBody,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.md),
          // Close + restore live under the CTA (per the design), not in the
          // top bar.
          Row(
            children: [
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Close',
                  onPressed: _busy ? null : _close,
                ),
              ),
              const SizedBox(width: BrandSpace.gutterSm),
              Expanded(
                child: BrandSecondaryButton(
                  label: 'Restore Purchases',
                  onPressed: _busy ? null : _restore,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          _LegalFooter(onManage: _manageSubscription),
        ],
      ),
    );
  }
}

/// The monthly-equivalent of an annual store price, formatted in the store's
/// own currency. Falls back to the design's static copy when billing isn't
/// configured.
String _perMonth(Package? pkg, {required String fallback}) {
  if (pkg == null) return fallback;
  final price = pkg.storeProduct.price;
  if (price <= 0) return fallback;
  final symbol = pkg.storeProduct.priceString.replaceAll(
    RegExp(r'[0-9.,\s\u00A0]'),
    '',
  );
  return NumberFormat.currency(
    symbol: symbol,
    decimalDigits: 2,
  ).format(price / 12);
}

String? _trialLabel(Package? pkg) {
  final intro = pkg?.storeProduct.introductoryPrice;
  if (intro == null) return null;
  final n = intro.periodNumberOfUnits;
  final unit = switch (intro.periodUnit.name) {
    'day' => 'day',
    'week' => 'week',
    'month' => 'month',
    'year' => 'year',
    _ => 'day',
  };
  return '$n-$unit free trial';
}

/// The real saving (%) of the annual pass vs paying monthly for a year — or
/// null when a package is missing or there's genuinely no saving. Never a
/// hard-coded marketing number.
int? _savePercent(Package? annual, Package? monthly) {
  if (annual == null || monthly == null) return null;
  final yearly = annual.storeProduct.price;
  final perYearAtMonthly = monthly.storeProduct.price * 12;
  if (yearly <= 0 || perYearAtMonthly <= 0 || yearly >= perYearAtMonthly) {
    return null;
  }
  return ((1 - yearly / perYearAtMonthly) * 100).round();
}

/// Whether annual is genuinely cheaper per month than monthly.
bool _annualIsBest(Package? annual, Package? monthly) {
  if (annual == null || monthly == null) return false;
  return annual.storeProduct.price / 12 < monthly.storeProduct.price;
}

/// The top bar carries only the design's "other" affordances: a back button,
/// the step dots, and the brand nav glyph. Close / Restore live under the CTA.
class _PaywallHeader extends StatelessWidget {
  const _PaywallHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BrandSpace.sm),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(bottom: BorderSide(color: BrandColors.hairline)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: BrandColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: BrandColors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? BrandColors.primaryContainer
                          : BrandColors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 44,
            width: 44,
            child: Icon(
              Icons.navigation_rounded,
              size: 24,
              color: BrandColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 104,
          width: 104,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Ambient glow.
              Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BrandColors.primaryContainer.withValues(alpha: 0.16),
                  boxShadow: [
                    BoxShadow(
                      color: BrandColors.primaryContainer.withValues(
                        alpha: 0.18,
                      ),
                      blurRadius: 48,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  borderRadius: BrandRadii.cardRadius,
                  color: BrandColors.surface,
                  boxShadow: BrandShadows.pod,
                ),
                child: Center(
                  child: Container(
                    height: 64,
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BrandRadii.miniRadius,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          BrandColors.primary,
                          BrandColors.primaryContainer,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.explore_rounded,
                      size: 34,
                      color: BrandColors.onPrimary,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.onSurface,
                    borderRadius: BrandRadii.pill,
                    boxShadow: BrandShadows.subtle,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 12,
                        color: BrandColors.primaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'PRO PASS',
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.surface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrandSpace.lg),
        BrandTag(
          icon: Icons.groups_rounded,
          label: 'UPGRADE CONVOY ACCESS',
          background: BrandColors.secondaryContainer,
          foreground: BrandColors.onSecondaryFixedVariant,
        ),
        const SizedBox(height: 10),
        Text(
          'Unlock the Ultimate Road Trip Experience',
          textAlign: TextAlign.center,
          style: BrandText.headlineLg.copyWith(color: BrandColors.textHeadline),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text.rich(
            TextSpan(
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
              children: [
                const TextSpan(text: 'One member goes Pro, the '),
                TextSpan(
                  text: 'entire convoy',
                  style: BrandText.weight(
                    BrandText.bodyMd,
                    700,
                  ).copyWith(color: BrandColors.primary),
                ),
                const TextSpan(text: ' unlocks Voice, 3D terrains & AI tools.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _AmbientTripCard extends ConsumerWidget {
  const _AmbientTripCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shows the user's *real* convoy when one is live — never sample data. With
    // no active trip it falls back to a neutral brand line.
    final trip = ref.watch(activeTripProvider).valueOrNull;
    final members = trip == null
        ? const <Map<String, dynamic>>[]
        : ref.watch(tripMembersProvider(trip.id)).valueOrNull ??
              const <Map<String, dynamic>>[];
    final avatars = <String>[
      for (final m in members)
        (m['profiles'] as Map<String, dynamic>?)?['avatar_id'] as String? ??
            kDefaultAvatarSeed,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.podRadius,
        boxShadow: BrandShadows.ambient,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BrandRadii.miniRadius,
            child: Image.asset(
              'assets/images/paywall/trip.jpg',
              height: 64,
              width: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => SizedBox(
                height: 64,
                width: 64,
                child: ColoredBox(color: BrandColors.surfaceContainerHigh),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (trip != null) ...[
                      Container(
                        height: 8,
                        width: 8,
                        decoration: BoxDecoration(
                          color: BrandColors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        trip != null ? 'CONVOY SYNC ACTIVE' : 'RANMAP CONVOY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.weight(BrandText.labelSm, 700)
                            .copyWith(
                              color: trip != null
                                  ? BrandColors.primary
                                  : BrandColors.textMuted,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  trip?.title ?? 'Your crew, one map',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.labelMd.copyWith(
                    color: BrandColors.onSurface,
                  ),
                ),
                Text(
                  trip != null ? '${members.length} in convoy' : 'Live location, voice and stops sync for everyone on the trip.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
                ),
              ],
            ),
          ),
          if (avatars.isNotEmpty) ...[
            const SizedBox(width: 8),
            _AvatarStack(avatars: avatars),
          ],
        ],
      ),
    );
  }
}

/// The real convoy members' avatars (up to 3, then `+N`).
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.avatars});

  final List<String> avatars;

  @override
  Widget build(BuildContext context) {
    final shown = avatars.take(3).toList();
    final extra = avatars.length - shown.length;
    final slots = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      height: 28,
      width: 28 + 18.0 * (slots - 1),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: 18.0 * i,
              child: Container(
                height: 28,
                width: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: BrandColors.surface,
                  shape: BoxShape.circle,
                ),
                child: AvatarView(
                  seed: shown[i],
                  size: 24,
                  background: BrandColors.surfaceContainerLow,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: 18.0 * shown.length,
              child: Container(
                height: 28,
                width: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BrandColors.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: BrandColors.surface, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: BrandText.labelSm.copyWith(
                    color: BrandColors.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComparisonRow {
  const _ComparisonRow(
    this.label,
    this.free,
    this.pro, {
    this.proIsCheck = false,
  });

  final String label;
  final String free;
  final String pro;
  final bool proIsCheck;
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  static final List<_ComparisonRow> _rows = [
    const _ComparisonRow(
      'Active Triplists',
      '$kFreeTripLimit Trips',
      'Unlimited',
    ),
    const _ComparisonRow(
      'Convoy Members',
      'Up to $kFreeGroupMemberLimit',
      '20+ Crew',
    ),
    const _ComparisonRow(
      'Photo Map Pins',
      '$kFreeMapPostLimit pins',
      'Uncapped',
    ),
    const _ComparisonRow('Voice Channels & AI', 'Locked', '', proIsCheck: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BrandSpace.md),
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.podRadius,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Tier Capability',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  'Free',
                  style: BrandText.labelSm.copyWith(color: BrandColors.outline),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BrandRadii.pill,
                  ),
                  child: Text(
                    'Pro Member',
                    style: BrandText.weight(
                      BrandText.labelSm,
                      700,
                    ).copyWith(color: BrandColors.primary),
                  ),
                ),
              ],
            ),
          ),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.surface.withValues(alpha: 0.7),
                  borderRadius: BrandRadii.miniRadius,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.bodyMd.copyWith(
                          color: BrandColors.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.free,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.labelSm.copyWith(
                          color: BrandColors.outline,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: row.proIsCheck
                            ? Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: BrandColors.primary,
                              )
                            : Text(
                                row.pro,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BrandText.weight(
                                  BrandText.labelSm,
                                  700,
                                ).copyWith(color: BrandColors.primary),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Benefit {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.body,
    required this.tint,
    required this.iconColor,
    this.chip,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tint;
  final Color iconColor;
  final String? chip;
}

class _Benefits extends StatelessWidget {
  static final List<_Benefit> _items = [
    _Benefit(
      icon: Icons.smart_toy_rounded,
      title: 'Autonomous AI Trip Copilot',
      body: 'Unlimited route brainstorming, instant hidden-gem lookup, and automated stop rescheduling on the fly.',
      tint: BrandColors.primaryContainer.withValues(alpha: 0.2),
      iconColor: BrandColors.primary,
    ),
    _Benefit(
      icon: Icons.mic_rounded,
      title: 'Unlimited LiveKit Voice',
      body: 'Walkie-talkie style low-latency voice channels for all vehicles in your party. No external apps required.',
      tint: BrandColors.secondaryFixed,
      iconColor: BrandColors.onSecondaryFixedVariant,
      chip: 'Convoy-wide',
    ),
    _Benefit(
      icon: Icons.landscape_rounded,
      title: 'Full 3D Terrain & Unlimited Search',
      body: 'Topographical pitch elevation, scenic ridge views, and unmetered discovery pins along your path.',
      tint: BrandColors.accentPeach,
      iconColor: BrandColors.onTertiaryFixedVariant,
    ),
    _Benefit(
      icon: Icons.analytics_rounded,
      title: 'Lifetime Telemetry & Fuel Rollup',
      body: 'Complete convoy expense splitting, gas efficiency tracking, and driving duration analytics per trip.',
      tint: BrandColors.surfaceContainerHigh,
      iconColor: BrandColors.onSurface,
    ),
    _Benefit(
      icon: Icons.add_a_photo_rounded,
      title: 'Unlimited Photo Map Pins',
      body:
          'Break past the $kFreeMapPostLimit photo free cap. Pin hundreds of geotagged memories directly onto your expedition route.',
      tint: BrandColors.surfaceContainerHigh,
      iconColor: BrandColors.onSurface,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            "What's included in Pro",
            style: BrandText.titleMd.copyWith(color: BrandColors.onSurface),
          ),
        ),
        for (final b in _items) ...[
          _BenefitCard(benefit: b),
          if (b != _items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({required this.benefit});

  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BrandRadii.cardRadius,
        boxShadow: BrandShadows.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: benefit.tint,
              borderRadius: BrandRadii.miniRadius,
            ),
            child: Icon(benefit.icon, size: 22, color: benefit.iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        benefit.title,
                        style: BrandText.labelLg.copyWith(
                          color: BrandColors.onSurface,
                        ),
                      ),
                    ),
                    if (benefit.chip != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.secondaryContainer,
                          borderRadius: BrandRadii.pill,
                        ),
                        child: Text(
                          benefit.chip!,
                          style: BrandText.labelSm.copyWith(
                            color: BrandColors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  benefit.body,
                  style: BrandText.bodyMd.copyWith(
                    color: BrandColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the store has no offering to sell — no invented prices.
class _PricingUnavailable extends StatelessWidget {
  const _PricingUnavailable();

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.all(BrandSpace.md),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: BrandColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Plans aren’t available right now. Please try again later.',
              style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSelector extends StatelessWidget {
  const _PlanSelector({
    required this.plan,
    required this.annualTotal,
    required this.annualPerMonth,
    required this.monthlyPrice,
    required this.trial,
    required this.showAnnual,
    required this.showMonthly,
    required this.onSelect,
    this.savePercent,
    this.annualIsBest = false,
  });
  final PaywallPlan plan;
  final String annualTotal;
  final String annualPerMonth;
  final String monthlyPrice;
  final String? trial;

  /// Which plans the store actually sells.
  final bool showAnnual;
  final bool showMonthly;

  /// Real saving (%) of annual vs 12× monthly, or null when it can't be
  /// derived — then no saving claim is shown.
  final int? savePercent;
  final bool annualIsBest;
  final ValueChanged<PaywallPlan> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Choose your pass',
                style: BrandText.labelMd.copyWith(color: BrandColors.onSurface),
              ),
              Text(
                'Cancel anytime',
                style: BrandText.labelSm.copyWith(color: BrandColors.outline),
              ),
            ],
          ),
        ),
        if (showAnnual)
          _PlanCard(
            selected: plan == PaywallPlan.annual,
            title: 'Annual Pro Pass',
            // Only claim "best value"/savings when the store's own prices bear
            // it out.
            badge: annualIsBest ? 'BEST VALUE' : null,
            ribbon: savePercent != null ? 'SAVE $savePercent%' : null,
            subtitle: trial != null
                ? '$trial, then $annualTotal/year'
                : '$annualTotal/year',
            figure: annualPerMonth,
            term: '/month',
            onTap: () => onSelect(PaywallPlan.annual),
          ),
        if (showAnnual && showMonthly) const SizedBox(height: 12),
        if (showMonthly)
          _PlanCard(
            selected: plan == PaywallPlan.monthly,
            title: 'Monthly Pass',
            subtitle: 'Flexible pay-as-you-go',
            figure: monthlyPrice,
            term: '/month',
            onTap: () => onSelect(PaywallPlan.monthly),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.figure,
    required this.term,
    required this.onTap,
    this.badge,
    this.ribbon,
  });

  final bool selected;
  final String title;
  final String? badge;
  final String? ribbon;
  final String subtitle;
  final String figure;
  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrandPressable(
      onTap: onTap,
      borderRadius: BrandRadii.cardRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(BrandSpace.md),
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BrandRadii.cardRadius,
          border: Border.all(
            color: selected ? BrandColors.primaryContainer : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected ? BrandShadows.pod : BrandShadows.subtle,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Container(
                  height: 20,
                  width: 20,
                  decoration: BoxDecoration(
                    color: selected
                        ? BrandColors.primary
                        : BrandColors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: BrandColors.onPrimary,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: BrandText.labelLg.copyWith(
                                color: BrandColors.onSurface,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: BrandColors.secondaryContainer
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge!,
                                style: BrandText.labelSm.copyWith(
                                  color: BrandColors.onSecondaryFixed,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: BrandText.bodyMd.copyWith(
                          color: BrandColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      figure,
                      style: BrandText.headlineMd.copyWith(
                        color: BrandColors.onSurface,
                      ),
                    ),
                    Text(
                      term,
                      style: BrandText.labelSm.copyWith(
                        color: BrandColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (ribbon != null)
              Positioned(
                top: -26,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.primaryContainer,
                    borderRadius: BrandRadii.pill,
                  ),
                  child: Text(
                    ribbon!,
                    style: BrandText.weight(
                      BrandText.labelSm,
                      700,
                    ).copyWith(color: BrandColors.onPrimaryContainer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.onManage});

  final VoidCallback onManage;

  /// Only the links that are actually configured, then the store action.
  List<Widget> _items(BuildContext context, TextStyle link) {
    final terms = Env.termsUrl;
    final privacy = Env.privacyUrl;
    return [
      if (terms != null)
        GestureDetector(
          onTap: () => _openExternal(context, terms),
          behavior: HitTestBehavior.opaque,
          child: Text('Terms of Service', style: link),
        ),
      if (privacy != null)
        GestureDetector(
          onTap: () => _openExternal(context, privacy),
          behavior: HitTestBehavior.opaque,
          child: Text('Privacy Policy', style: link),
        ),
      GestureDetector(
        onTap: onManage,
        behavior: HitTestBehavior.opaque,
        child: Text(
          'Manage Subscription',
          style: BrandText.labelSm.copyWith(color: BrandColors.primary),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final link = BrandText.labelSm.copyWith(color: BrandColors.outline);
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            for (final (i, item) in _items(context, link).indexed) ...[
              if (i > 0) Text('•', style: link),
              item,
            ],
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Secured via Apple App Store & Google Play Billing. Payment will be charged upon trial '
            'conclusion unless canceled 24 hours prior.',
            textAlign: TextAlign.center,
            style: BrandText.labelSm.copyWith(color: BrandColors.outline),
          ),
        ),
      ],
    );
  }
}
