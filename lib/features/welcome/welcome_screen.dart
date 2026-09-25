import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/theme/nav_palette.dart';

/// A single intro slide.
class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Color> colors;
}

const _slides = <_Slide>[
  _Slide(
    icon: Icons.near_me_rounded,
    title: 'Track your crew, live',
    body: 'See everyone’s position on a real 3D map as you drive — together, in real time.',
    colors: [Color(0xFF1A73E8), Color(0xFF4C9AF5)],
  ),
  _Slide(
    icon: Icons.alt_route_rounded,
    title: 'Plan the route',
    body: 'Pick a start and destination, compare alternate routes, and follow them turn by turn.',
    colors: [Color(0xFF0E7490), Color(0xFF22B8D6)],
  ),
  _Slide(
    icon: Icons.headset_mic_rounded,
    title: 'Talk hands-free',
    body: 'Hop on a voice channel with your group and keep the conversation going on the road.',
    colors: [Color(0xFF4338CA), Color(0xFF7C3AED)],
  ),
  _Slide(
    icon: Icons.receipt_long_rounded,
    title: 'Keep the trip log',
    body: 'Log stops, fuel and expenses, and pin photos right to the route as you go.',
    colors: [Color(0xFF1A73E8), Color(0xFF0EA5E9)],
  ),
];

/// The pre-auth intro carousel. Shown once on first launch, before sign-in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(appPrefsProvider).markIntroSeen();
    if (mounted) context.go('/sign-in');
  }

  void _next() {
    if (_index == _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    final last = _index == _slides.length - 1;

    return FScaffold(
      childPad: false,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: FButton(
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: _finish,
                  child: Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  _Dots(count: _slides.length, index: _index, color: c.activeRoute),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FButton(
                      size: .lg,
                      onPress: _finishing ? null : _next,
                      child: Text(last ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: slide.colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: slide.colors.first.withValues(alpha: 0.35),
                  offset: const Offset(0, 18),
                  blurRadius: 40,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -40,
                  right: -30,
                  child: _Blob(color: Colors.white.withValues(alpha: 0.14), size: 160),
                ),
                Positioned(
                  bottom: -50,
                  left: -40,
                  child: _Blob(color: Colors.white.withValues(alpha: 0.10), size: 200),
                ),
                Container(
                  height: 128,
                  width: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Icon(slide.icon, size: 60, color: Colors.white),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 420.ms, curve: Curves.easeOut)
              .scale(begin: const Offset(0.94, 0.94), end: const Offset(1, 1), curve: Curves.easeOutBack),
          const SizedBox(height: 40),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15, color: c.foreground),
          ).animate().fadeIn(delay: 120.ms, duration: 360.ms).slideY(begin: 0.25, end: 0, curve: Curves.easeOut),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4, color: c.mutedForeground),
          ).animate().fadeIn(delay: 220.ms, duration: 360.ms).slideY(begin: 0.25, end: 0, curve: Curves.easeOut),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.color});

  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: i == index ? 26 : 8,
            decoration: BoxDecoration(
              color: i == index ? color : c.border,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
      ],
    );
  }
}
