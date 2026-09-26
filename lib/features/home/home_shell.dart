import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../chat/chat_hub_screen.dart';
import '../premium/paywall_gate.dart';
import '../trip/trip_list_screen.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';

/// Bottom-nav shell hosting the four primary destinations.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Tabs are built lazily on first visit, so the map's GPS/permission work and
  /// the profile's provider fan-out don't all fire at launch. Once visited a tab
  /// stays mounted (IndexedStack preserves state).
  final Set<int> _visited = {0};

  static const _screens = [
    MapScreen(),
    TripListScreen(),
    ChatHubScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      // Screens own their own padding/background (the map especially).
      childPad: false,
      footer: FBottomNavigationBar(
        index: _index,
        onChange: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
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
      // Surfaces the non-Pro paywall once after onboarding and weekly after.
      child: PaywallGate(
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
