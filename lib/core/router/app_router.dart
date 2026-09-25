import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/welcome/welcome_screen.dart';
import '../providers/app_prefs_provider.dart';
import 'auth_state_provider.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  // Listen to auth/profile so redirects re-run, but don't *watch* them here:
  // watching would rebuild (and reset) the whole GoRouter on every auth event.
  final refresh = _RiverpodRefreshStream(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final profileAsync = ref.read(myProfileProvider);
      final introSeen = ref.read(appPrefsProvider).introSeen;

      final signedIn = authAsync.valueOrNull?.session != null;
      final loc = state.matchedLocation;
      final loggingInRoute = loc == '/sign-in' || loc == '/sign-up';
      final welcomeRoute = loc == '/welcome';

      if (!signedIn) {
        // First launch: show the intro carousel before the auth screens.
        if (!introSeen) return welcomeRoute ? null : '/welcome';
        if (welcomeRoute) return '/sign-in';
        return loggingInRoute ? null : '/sign-in';
      }

      // Signed in: wait for profile lookup before deciding onboarding vs home.
      if (profileAsync.isLoading) return null;

      // If the lookup failed (offline, transient error), don't treat it as
      // "no profile" — that would bounce a fully onboarded user into
      // /onboarding, where finishing would collide on the profile's PK.
      if (profileAsync.hasError) return null;

      final hasProfile = profileAsync.valueOrNull != null;
      final onboardingRoute = state.matchedLocation == '/onboarding';

      if (!hasProfile) {
        return onboardingRoute ? null : '/onboarding';
      }

      if (onboardingRoute || loggingInRoute || welcomeRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeShell()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (context, state) => const SignUpScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    ],
  );
});

/// Bridges Riverpod's AsyncValue streams into a [Listenable] go_router can
/// watch for its `refreshListenable` redirect trigger.
class _RiverpodRefreshStream extends ChangeNotifier {
  _RiverpodRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, next) => notifyListeners());
    ref.listen(myProfileProvider, (_, next) => notifyListeners());
  }
}
