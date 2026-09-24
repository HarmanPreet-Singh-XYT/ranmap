import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import 'premium_providers.dart';
import 'premium_purchaser.dart';
import 'revenuecat.dart';

/// A paid capability. The [key] matches the server's `PremiumFeature` values for
/// the server-gated features; the client-only ones (history/trips/photos/group
/// size) are enforced by DB triggers and just need a label here.
enum PremiumFeature {
  aiAssistant('ai_assistant', 'AI assistant'),
  voice('voice', 'voice channels'),
  mapsSearch('maps_search', 'route & place search'),
  history('history', 'trip stats & history'),
  trips('trips', 'planned trips'),
  photos('photos', 'map photos'),
  groupSize('group_size', 'group size');

  const PremiumFeature(this.key, this.label);

  final String key;
  final String label;
}

/// What Pro unlocks. Kept in one place so the paywall and its teasers agree.
const _benefits = <({IconData icon, String title, String detail})>[
  (
    icon: Icons.auto_awesome_rounded,
    title: 'Unlimited AI trip assistant',
    detail: 'Plan routes, save places, and schedule trips by chatting.',
  ),
  (
    icon: Icons.mic_rounded,
    title: 'Voice channels',
    detail: 'Talk live with your crew on any trip or group.',
  ),
  (
    icon: Icons.route_rounded,
    title: 'Unlimited route & place search',
    detail: 'No daily cap on planning and nearby places.',
  ),
  (
    icon: Icons.groups_rounded,
    title: 'Travel together',
    detail: 'If anyone on your trip has Pro, everyone gets voice — no per-seat cost.',
  ),
];

/// Opens the Ranmap Pro paywall, e.g. after a 402 from the backend
/// ([isPremiumRequired]).
Future<void> showPaywall(BuildContext context, {required PremiumFeature feature}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(premiumPurchaserProvider).restore();
      ref.invalidate(entitlementsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Purchases restored.')));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Ranmap Pro', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text('You reached a Pro limit for ${widget.feature.label}.'),
            const SizedBox(height: 16),
            for (final benefit in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(benefit.icon, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(benefit.title,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(benefit.detail, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _purchase,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Start Ranmap Pro'),
            ),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore purchases'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
