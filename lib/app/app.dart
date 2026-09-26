import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/providers/settings_provider.dart';
import '../core/router/app_router.dart';
import '../core/theme/brand_palette.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/forui_theme.dart';
import '../core/widgets/offline_banner.dart';

class RanmapApp extends ConsumerWidget {
  const RanmapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(appSettingsProvider.select((s) => s.themeMode));

    return MaterialApp.router(
      title: 'Ranmap',
      debugShowCheckedModeBanner: false,
      // Material widgets (SnackBar, native pickers, the Mapbox platform view's
      // host) follow a matching Material theme.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      routerConfig: router,
      // Surface connectivity loss app-wide without covering any content.
      builder: (context, child) {
        // Point the ambient brand tokens at the active brightness, so every
        // `BrandColors.x` call site follows light/dark without extra plumbing.
        final dark = Theme.brightnessOf(context) == Brightness.dark;
        BrandColors.use(dark ? BrandPalette.dark : BrandPalette.light);
        return FTheme(
          data: dark ? darkNavTheme : lightNavTheme,
          child: FToaster(
            child: FTooltipGroup(
              child: OfflineBanner(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
