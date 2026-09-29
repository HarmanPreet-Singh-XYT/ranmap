import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_sheet_surface.dart';
import 'premium_providers.dart';
import 'premium_purchaser.dart';
import 'revenuecat.dart';

/// A paid capability. The [key] matches the server's `PremiumFeature` values for
/// the server-gated features (ai_assistant/voice/maps_search); the rest are
/// client-only gates — some backed by DB triggers (trips/photos/group
/// size/documents/route templates), the others plain UI locks (history,
/// offline maps, service, weather, recap) — and just need a label here.
enum PremiumFeature {
  aiAssistant('ai_assistant', 'AI assistant'),
  voice('voice', 'voice channels'),
  mapsSearch('maps_search', 'route & place search'),
  history('history', 'trip stats & history'),
  trips('trips', 'planned trips'),
  photos('photos', 'map photos'),
  groupSize('group_size', 'group size'),
  offlineMaps('offline_maps', 'offline maps'),
  documents('documents', 'documents'),
  service('service', 'service reminders'),
  routeTemplates('route_templates', 'saved routes'),
  weather('weather', 'weather en route'),
  recap('recap', 'trip recap export');

  const PremiumFeature(this.key, this.label);

  final String key;
  final String label;
}

/// What Pro unlocks. Kept in one place so the paywall and its teasers agree.
const _benefits = <({IconData icon, String title, String detail})>[
  (
    icon: Icons.auto_awesome_rounded,
    title: 'A generous AI planning allowance',
    detail: 'Plan routes, save places, and schedule trips by chatting.',
  ),
  (
    icon: Icons.mic_rounded,
    title: 'Voice channels',
    detail: 'Talk live with your crew on any trip or group.',
  ),
  (
    icon: Icons.route_rounded,
    title: 'A generous search allowance',
    detail: 'Far more route and nearby-place searches every day.',
  ),
  (
    icon: Icons.map_outlined,
    title: 'Offline maps',
    detail: 'Save your route area and keep navigating with no signal.',
  ),
  (
    icon: Icons.folder_copy_outlined,
    title: 'Documents vault',
    detail: 'Keep licence, insurance and tickets in a private wallet.',
  ),
  (
    icon: Icons.build_circle_outlined,
    title: 'Service reminders & full history',
    detail: 'Track maintenance and your complete trip logbook.',
  ),
  (
    icon: Icons.groups_rounded,
    title: 'Travel together',
    detail: 'If anyone on your trip has Pro, everyone gets voice — no per-seat cost.',
  ),
];

/// Opens the Ranmap Pro paywall, e.g. after a 402 from the backend
/// ([isPremiumRequired]).
Future<void> showPaywall(
  BuildContext context, {
  required PremiumFeature feature,
}) {
  return showFSheet(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (_) => _PaywallSheet(feature: feature),
  );
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet({required this.feature});

  final PremiumFeature feature;

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  bool _busy = false;

  Future<void> _purchase() async {
    setState(() => _busy = true);
    try {
      await ref.read(premiumPurchaserProvider).purchase();
      // A successful purchase flips the plan server-side; refetch it.
      ref.invalidate(entitlementsProvider);
      if (mounted) Navigator.of(context).pop();
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
      if (mounted && restored) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return BrandSheetSurface(
      handle: false,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.activeRoute, const Color(0xFF7C3AED)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ranmap Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You reached a Pro limit for ${widget.feature.label}.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final benefit in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(benefit.icon, color: c.activeRoute),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: c.foreground,
                            ),
                          ),
                          Text(
                            benefit.detail,
                            style: TextStyle(
                              color: c.mutedForeground,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FButton(
              size: .lg,
              onPress: _busy ? null : _purchase,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: AppSpinner(color: Colors.white),
                    )
                  : const Text('Start Ranmap Pro'),
            ),
            FButton(
              variant: .ghost,
              onPress: _busy ? null : _restore,
              child: const Text('Restore purchases'),
            ),
            FButton(
              variant: .ghost,
              onPress: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
