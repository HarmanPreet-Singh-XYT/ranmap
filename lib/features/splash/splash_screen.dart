import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Held while the session and profile resolve, so a returning signed-in user
/// never flashes the pre-auth tour/welcome (and a signed-in user is never
/// stranded on a pre-auth screen if the profile fetch fails).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      childPad: false,
      child: Center(child: FCircularProgress()),
    );
  }
}
