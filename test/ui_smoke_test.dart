import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ranmap/core/providers/app_prefs_provider.dart';
import 'package:ranmap/core/theme/forui_theme.dart';
import 'package:ranmap/core/widgets/app_dialog.dart';
import 'package:ranmap/core/widgets/avatar_view.dart';
import 'package:ranmap/core/widgets/nav_surface.dart';
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

void main() {
  testWidgets('welcome carousel renders and advances', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _app(
        const WelcomeScreen(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Track your crew, live'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Plan the route'), findsOneWidget);
  });

  testWidgets('FScaffold + FTabs(expands) lays out without errors', (tester) async {
    await tester.pumpWidget(
      _app(
        FScaffold(
          childPad: false,
          header: const FHeader(title: Text('Tabs')),
          child: FTabs(
            expands: true,
            children: const [
              FTabEntry(label: Text('One'), child: Center(child: Text('first'))),
              FTabEntry(label: Text('Two'), child: Center(child: Text('second'))),
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
  testWidgets('FScaffold + footer nav + IndexedStack lays out (home shell shape)', (tester) async {
    await tester.pumpWidget(
      _app(
        FScaffold(
          childPad: false,
          footer: FBottomNavigationBar(
            index: 0,
            onChange: (_) {},
            children: const [
              FBottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: Text('Map')),
              FBottomNavigationBarItem(icon: Icon(Icons.route_rounded), label: Text('Trips')),
              FBottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: Text('Chat')),
              FBottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: Text('Profile')),
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
  });

  // Mirrors MapScreen: a full-bleed map under floating overlays, inside FScaffold.
  testWidgets('FScaffold + Stack + FloatingPanel lays out (map screen shape)', (tester) async {
    await tester.pumpWidget(
      _app(
        FScaffold(
          childPad: false,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFFEFEBE9))),
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
}
