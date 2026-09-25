import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../chat/chat_hub_screen.dart';
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
        onChange: (i) => setState(() => _index = i),
        children: const [
          FBottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: Text('Map')),
          FBottomNavigationBarItem(icon: Icon(Icons.route_rounded), label: Text('Trips')),
          FBottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: Text('Chat')),
          FBottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: Text('Profile')),
        ],
      ),
      child: IndexedStack(index: _index, children: _screens),
    );
  }
}
