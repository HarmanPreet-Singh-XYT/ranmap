import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/constants/invite_links.dart';
import '../core/providers/settings_provider.dart';
import '../core/router/app_router.dart';
import '../core/router/auth_state_provider.dart';
import '../core/theme/brand_palette.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/forui_theme.dart';
import '../core/widgets/offline_banner.dart';
import '../features/social/invite_providers.dart';

class RanmapApp extends ConsumerStatefulWidget {
  const RanmapApp({super.key});

  @override
  ConsumerState<RanmapApp> createState() => _RanmapAppState();
}

class _RanmapAppState extends ConsumerState<RanmapApp> {
  final _links = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // The link that launched the app, then every link that arrives while it's
    // running. Both are routed to the invite screen (and remembered so a
    // signed-out recipient is offered it again after sign-up).
    unawaited(_handleInitialLink());
    _linkSub = _links.uriLinkStream.listen(
      _handleUri,
      onError: (_) {
        // An unparseable/unsupported link must not take the app down.
      },
    );
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    super.dispose();
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _links.getInitialLink();
      if (uri != null) _handleUri(uri);
    } catch (_) {
      // No link / platform without deep-link support — nothing to do.
    }
  }

  void _handleUri(Uri uri) {
    // A group join link (`.../join/<code>`) takes precedence: it's a distinct
    // scheme host / path from a friend invite.
    final code = groupJoinCodeFromUri(uri);
    if (code != null && code.isNotEmpty) {
      // A signed-in user joins now; a signed-out one keeps the code so
      // [HomeShell] re-opens this screen after sign-up. Clearing it here for
      // the signed-in case avoids [HomeShell] pushing a duplicate on top of
      // the `go` below.
      final signedIn = ref.read(authStateProvider).valueOrNull?.session != null;
      if (signedIn) {
        unawaited(ref.read(pendingGroupJoinProvider.notifier).clear());
      } else {
        unawaited(ref.read(pendingGroupJoinProvider.notifier).set(code));
      }
      ref.read(goRouterProvider).go('/join/$code');
      return;
    }

    final username = inviteUsernameFromUri(uri);
    if (username == null || username.isEmpty) return;
    // Persist before navigating: the value must outlive this process for the
    // sign-up round trip.
    unawaited(ref.read(pendingInviteProvider.notifier).set(username));
    ref.read(goRouterProvider).go('/invite/$username');
  }

  @override
  Widget build(BuildContext context) {
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
          child: _ThemeRefresher(
            child: FToaster(
              child: FTooltipGroup(
                child: OfflineBanner(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `BrandColors` is a global, not an inherited value, so widgets that only read
/// it aren't told when the brightness flips and keep their old colours. When the
/// brightness changes, this rebuilds everything below it (state is preserved).
class _ThemeRefresher extends StatefulWidget {
  const _ThemeRefresher({required this.child});

  final Widget child;

  @override
  State<_ThemeRefresher> createState() => _ThemeRefresherState();
}

class _ThemeRefresherState extends State<_ThemeRefresher> {
  Brightness? _brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.brightnessOf(context);
    final changed = _brightness != null && _brightness != brightness;
    _brightness = brightness;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildAll(context as Element);
      });
    }
  }

  static void _rebuildAll(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_rebuildAll);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
