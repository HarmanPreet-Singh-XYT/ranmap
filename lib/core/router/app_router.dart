import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/phone_verification_screen.dart';
import '../../features/premium/paywall_screen.dart';
import '../../features/social/invite_landing_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tour/tour_screen.dart';
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
    // A deep link that matches no route (e.g. an OAuth `.../login-callback`
    // URI that supabase_flutter didn't consume) would otherwise render
    // go_router's "no routes" error page. Land on '/' instead.
    onException: (context, state, router) => router.go('/'),
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final profileAsync = ref.read(myProfileProvider);
      final prefs = ref.read(appPrefsProvider);

      final loc = state.matchedLocation;
      final loggingInRoute = loc == '/sign-in' || loc == '/sign-up';
      final welcomeRoute = loc == '/welcome';
      final tourRoute = loc == '/tour';
      final onboardingRoute = loc == '/onboarding';
      final verifyRoute = loc == '/verify-phone';
      final splashRoute = loc == '/splash';
      // An invite link lands here. It must survive a signed-out (and
      // auth-still-loading) state, so the recipient can see who invited them
      // before signing up.
      final inviteRoute = loc.startsWith('/invite/');

      // Until the session is known, hold on the splash instead of treating
      // "loading" as "signed out" — which would flash the tour/welcome at a
      // returning user, or strand a signed-in user on a pre-auth screen. An
      // invite stays put rather than bouncing through the splash (which would
      // lose it).
      if (authAsync.isLoading) {
        return (splashRoute || inviteRoute) ? null : '/splash';
      }

      final signedIn = authAsync.valueOrNull?.session != null;

      if (!signedIn) {
        // The intro steps and the auth screens are always renderable, so
        // forward/back navigation between them (landing → welcome → auth) is
        // never bounced. From the splash, land on the correct intro step.
        if (splashRoute) return prefs.introV1Seen ? '/welcome' : '/tour';
        if (tourRoute || welcomeRoute || loggingInRoute || inviteRoute) {
          return null;
        }

        // Signed out, the landing is the feature tour until it's been walked,
        // and the welcome after that — so relaunching once the features are
        // done resumes on the welcome, not straight at sign-in.
        if (!prefs.introV1Seen) return '/tour';
        return '/welcome';
      }

      // Signed in: wait for the profile lookup before deciding onboarding vs
      // home. Staying put (rather than bouncing) avoids re-triggering the
      // splash when the profile provider is merely re-fetching.
      if (profileAsync.isLoading) return null;

      // If the lookup failed (offline, transient error), don't treat it as
      // "no profile" — that would bounce a fully onboarded user into
      // /onboarding, where finishing would collide on the profile's PK. But
      // never leave a signed-in user stranded on the splash or a pre-auth
      // screen; send them to the home shell, which surfaces its own errors.
      if (profileAsync.hasError) {
        if (splashRoute || onboardingRoute || loggingInRoute || welcomeRoute || tourRoute) {
          return '/';
        }
        return null;
      }

      final hasProfile = profileAsync.valueOrNull != null;

      // The verify step is reachable both mid-onboarding (the profile was just
      // created, so the provider briefly still reads null) and after it.
      if (verifyRoute) return null;

      if (!hasProfile) {
        return onboardingRoute ? null : '/onboarding';
      }

      if (onboardingRoute ||
          loggingInRoute ||
          welcomeRoute ||
          tourRoute ||
          splashRoute) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeShell()),
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/tour', builder: (context, state) => const TourScreen()),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/verify-phone',
        builder: (context, state) => const PhoneVerificationScreen(),
      ),
      // Full-screen Pro paywall (post-auth + weekly interstitial). Auth-gated
      // by the redirect above, so it's unreachable when signed out.
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const PaywallScreen(),
      ),
      // Opened by a shared invite link (`https://<host>/invite/<username>` or
      // `com.ranmap.app://invite/<username>`). Reachable signed in or out.
      GoRoute(
        path: '/invite/:username',
        builder: (context, state) => InviteLandingScreen(
          username: state.pathParameters['username'] ?? '',
        ),
      ),
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
