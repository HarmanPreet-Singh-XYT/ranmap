import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ranmap/core/providers/app_prefs_provider.dart';
import 'package:ranmap/core/router/auth_state_provider.dart';
import 'package:ranmap/core/theme/forui_theme.dart';
import 'package:ranmap/core/widgets/app_dialog.dart';
import 'package:ranmap/core/widgets/avatar_view.dart';
import 'package:ranmap/core/widgets/nav_surface.dart';
import 'package:ranmap/features/auth/sign_in_screen.dart';
import 'package:ranmap/features/auth/sign_up_screen.dart';
import 'package:ranmap/features/onboarding/onboarding_screen.dart';
import 'package:ranmap/data/models/profile.dart';
import 'package:ranmap/data/models/trip.dart';
import 'package:ranmap/data/repositories/notification_repository.dart';
import 'package:ranmap/features/onboarding/phone_verification_screen.dart';
import 'package:ranmap/features/premium/paywall_screen.dart';
import 'package:ranmap/features/profile/profile_screen.dart';
import 'package:ranmap/features/settings/settings_providers.dart';
import 'package:ranmap/features/settings/settings_screen.dart';
import 'package:ranmap/features/premium/premium_providers.dart';
import 'package:ranmap/features/premium/revenuecat.dart';
import 'package:ranmap/features/tour/tour_screen.dart';
import 'package:ranmap/features/trip/trip_list_screen.dart';
import 'package:ranmap/features/trip/trip_providers.dart';
import 'package:ranmap/features/welcome/welcome_screen.dart';

/// Wraps [child] in the app's real Forui theme + localizations, the way
/// `RanmapApp` does.
Widget _app(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      builder: (context, inner) => FTheme(
        data: lightNavTheme,
        child: FToaster(child: inner ?? const SizedBox.shrink()),
      ),
      home: child,
    ),
  );
}

/// Gives the test a tall viewport so a full-screen `ListView` builds every
/// child (otherwise the CTA below the fold is never laid out).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('welcome screen renders value prop and CTAs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _app(
        const WelcomeScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Drive Together'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('FScaffold + FTabs(expands) lays out without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        FScaffold(
          childPad: false,
          header: const FHeader(title: Text('Tabs')),
          child: FTabs(
            expands: true,
            children: const [
              FTabEntry(
                label: Text('One'),
                child: Center(child: Text('first')),
              ),
              FTabEntry(
                label: Text('Two'),
                child: Center(child: Text('second')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('first'), findsOneWidget);
  });

  testWidgets('ForUI confirm dialog renders and resolves', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => FScaffold(
            child: Center(
              child: FButton(
                onPress: () async {
                  confirmed = await showAppConfirmDialog(
                    context,
                    title: 'Delete thing?',
                    message: 'There is no undo.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                },
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Delete thing?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('ForUI sheet renders', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => FScaffold(
            child: Center(
              child: FButton(
                onPress: () => showFSheet(
                  context: context,
                  side: FLayout.btt,
                  builder: (_) => const SizedBox(
                    height: 140,
                    child: Center(child: Text('sheet body')),
                  ),
                ),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget);
  });

  testWidgets('Multiavatar avatar renders', (tester) async {
    await tester.pumpWidget(
      _app(const Center(child: AvatarView(seed: 'abc123def456', size: 64))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // The home shell mounts all four tabs at once, so any one of them throwing
  // surfaces here. This mirrors that exact construct.
  testWidgets(
    'FScaffold + footer nav + IndexedStack lays out (home shell shape)',
    (tester) async {
      await tester.pumpWidget(
        _app(
          FScaffold(
            childPad: false,
            footer: FBottomNavigationBar(
              index: 0,
              onChange: (_) {},
              children: const [
                FBottomNavigationBarItem(
                  icon: Icon(Icons.map_rounded),
                  label: Text('Map'),
                ),
                FBottomNavigationBarItem(
                  icon: Icon(Icons.route_rounded),
                  label: Text('Trips'),
                ),
                FBottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_rounded),
                  label: Text('Chat'),
                ),
                FBottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded),
                  label: Text('Profile'),
                ),
              ],
            ),
            child: const IndexedStack(
              index: 0,
              children: [
                Center(child: Text('map tab')),
                Center(child: Text('trips tab')),
                Center(child: Text('chat tab')),
                Center(child: Text('profile tab')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('map tab'), findsOneWidget);
    },
  );

  // Mirrors MapScreen: a full-bleed map under floating overlays, inside FScaffold.
  testWidgets('FScaffold + Stack + FloatingPanel lays out (map screen shape)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        FScaffold(
          childPad: false,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFEFEBE9)),
              ),
              const Positioned(
                top: 16,
                right: 16,
                child: FloatingPanel(child: Icon(Icons.my_location)),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: FloatingPanel(child: const Text('No active trip')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No active trip'), findsOneWidget);
  });

  testWidgets('brand create-account screen lays out', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const SignUpScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('brand trips tab lays out its empty state', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(
        const TripListScreen(),
        overrides: [
          myTripsProvider.overrideWith((ref) async => const <Trip>[]),
          tripInvitesProvider.overrideWith(
            (ref) async => const <Map<String, dynamic>>[],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('New trip'), findsOneWidget);
  });

  testWidgets('brand profile tab lays out', (tester) async {
    _useTallSurface(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _app(
        const ProfileScreen(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          myProfileProvider.overrideWith(
            (ref) async => const Profile(id: 'u1', username: 'tester'),
          ),
          revenueCatProProvider.overrideWith((ref) => Stream.value(false)),
          entitlementsProvider.overrideWith((ref) async => Entitlements.free),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Vehicle Garage'), findsOneWidget);
    expect(find.text('Pilot Rollup'), findsOneWidget);
    expect(find.text('Friends & Crew'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    // Free plan → the rollup is locked, not showing Pro numbers.
    expect(find.text('Unlock Pro stats'), findsOneWidget);
    expect(find.text('Total Distance'), findsNothing);
  });

  testWidgets('brand settings screen lays out', (tester) async {
    _useTallSurface(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _app(
        const SettingsScreen(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          myProfileProvider.overrideWith(
            (ref) async => const Profile(id: 'u1', username: 'tester'),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref) async => const NotificationPreferences(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Offline Data & Queue'), findsNothing);
  });

  testWidgets('brand sign-in screen lays out with social buttons', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to Ranmap'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('brand onboarding screen lays out', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const OnboardingScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Set up your pilot profile'), findsOneWidget);
    expect(find.text('Continue to Verification'), findsOneWidget);
  });

  testWidgets('brand phone verification screen lays out', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_app(const PhoneVerificationScreen()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Verify your phone number'), findsOneWidget);
    expect(find.text('Complete & Enter RanMap'), findsOneWidget);
  });

  testWidgets('feature tour renders and advances', (tester) async {
    _useTallSurface(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _app(
        const TourScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Never Lose Your Pack'), findsOneWidget);
    expect(find.text('Next: Audio Comms'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Walkie-Talkie in Your Pocket'), findsOneWidget);
    expect(find.text('Next: Smart Pitstops'), findsOneWidget);
  });

  testWidgets('paywall screen renders and toggles plan', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(
      _app(
        const PaywallScreen(),
        // Isolate from dotenv / Supabase / billing.
        overrides: [
          entitlementsProvider.overrideWith((ref) async => Entitlements.free),
          revenueCatProProvider.overrideWith((ref) => Stream.value(false)),
          paywallOfferingProvider.overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Ultimate Road Trip'), findsOneWidget);
    // No offering is configured, so no trial is advertised — the CTA must not
    // fabricate one.
    expect(find.textContaining('free trial'), findsNothing);
    expect(find.textContaining('Subscribe & Unlock Pro'), findsWidgets);
    // Close + restore sit below the CTA, not in the top bar.
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Restore Purchases'), findsOneWidget);

    await tester.tap(find.text('Monthly Pass'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unlock Monthly Pass'), findsOneWidget);
  });
}
