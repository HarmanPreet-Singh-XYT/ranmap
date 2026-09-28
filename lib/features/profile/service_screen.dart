import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/units.dart';
import '../../core/widgets/app_choice_sheet.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_data.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/error_retry.dart';
import '../trip/trip_providers.dart';
import 'profile_extras_providers.dart';

/// Vehicle service reminders. The odometer is the sum of recorded trip
/// distance, so the reminder works without any manual mileage entry.
class ServiceScreen extends ConsumerWidget {
  const ServiceScreen({super.key});

  static const _intervalOptions = <int>[5000, 10000, 15000, 20000, 30000];

  Future<void> _setInterval(
    BuildContext context,
    WidgetRef ref,
    double currentInterval,
    double lastService,
  ) async {
    final choice = await showAppChoiceSheet<int>(
      context,
      title: 'Service interval',
      selected: currentInterval.round(),
      options: [
        for (final km in _intervalOptions) (value: km, label: '$km km'),
      ],
    );
    if (choice == null) return;
    try {
      await ref
          .read(vehicleServiceRepositoryProvider)
          .save(intervalKm: choice.toDouble(), lastServiceKm: lastService);
      ref.invalidate(vehicleServiceProvider);
      if (context.mounted) showAppToast(context, 'Service interval updated.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _markServiced(
    BuildContext context,
    WidgetRef ref,
    double interval,
    double odometer,
  ) async {
    try {
      await ref
          .read(vehicleServiceRepositoryProvider)
          .save(intervalKm: interval, lastServiceKm: odometer);
      ref.invalidate(vehicleServiceProvider);
      if (context.mounted) showAppToast(context, 'Marked as serviced.');
    } catch (e) {
      if (context.mounted) showAppToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(appSettingsProvider.select((s) => s.distanceUnit));
    final serviceAsync = ref.watch(vehicleServiceProvider);
    final odometerAsync = ref.watch(odometerKmProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Service & maintenance',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: serviceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(vehicleServiceProvider),
        ),
        data: (service) {
          final odometer = (odometerAsync.valueOrNull ?? 0).toDouble();
          final since = (odometer - service.lastServiceKm)
              .clamp(0.0, double.infinity)
              .toDouble();
          final remaining = service.intervalKm - since;
          final due = remaining <= 0;
          final overdue = due ? -remaining : 0.0;

          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            children: [
              BrandCard(
                padding: const EdgeInsets.all(BrandSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrandSectionHeader(
                      icon: Icons.build_circle_outlined,
                      title: due ? 'Service due' : 'Next service',
                      trailing: BrandPill(
                        bold: true,
                        label: due
                            ? 'Overdue ${formatDistance(overdue, unit, decimals: 0)}'
                            : 'in ${formatDistance(remaining, unit, decimals: 0)}',
                        background: due ? BrandColors.errorContainer : null,
                        foreground: due ? BrandColors.error : null,
                      ),
                    ),
                    const SizedBox(height: BrandSpace.md),
                    BrandProgressBar(value: since / service.intervalKm),
                    const SizedBox(height: BrandSpace.md),
                    BrandStatGrid(
                      tiles: [
                        BrandStatTile(
                          label: 'Odometer',
                          value: formatDistance(odometer, unit, decimals: 0),
                          icon: Icons.speed_rounded,
                        ),
                        BrandStatTile(
                          label: 'Since service',
                          value: formatDistance(since, unit, decimals: 0),
                          icon: Icons.history_rounded,
                        ),
                        BrandStatTile(
                          label: 'Interval',
                          value: formatDistance(
                            service.intervalKm,
                            unit,
                            decimals: 0,
                          ),
                          icon: Icons.event_repeat_rounded,
                        ),
                        BrandStatTile(
                          label: 'Last service',
                          value: formatDistance(
                            service.lastServiceKm,
                            unit,
                            decimals: 0,
                          ),
                          icon: Icons.build_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BrandSpace.lg),
              BrandSecondaryButton(
                label: 'Change interval',
                leading: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: BrandColors.textHeadlineAlt,
                ),
                onPressed: () => _setInterval(
                  context,
                  ref,
                  service.intervalKm,
                  service.lastServiceKm,
                ),
              ),
              const SizedBox(height: BrandSpace.sm),
              BrandPrimaryButton(
                label: 'Mark as serviced',
                leadingIcon: Icons.check_circle_outline_rounded,
                onPressed: () =>
                    _markServiced(context, ref, service.intervalKm, odometer),
              ),
              const SizedBox(height: BrandSpace.sm),
              Text(
                'The odometer is the distance of every trip you have recorded, '
                'so there is nothing to enter by hand.',
                style: BrandText.bodySm.copyWith(color: BrandColors.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}
