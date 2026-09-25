import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/services/supabase_service.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/brand_mark.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.signInWithPassword(email: email, password: password);
      // Router redirect handles navigation once the auth state changes.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email address first, then tap "Forgot password?"');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      showAppToast(context, 'If an account exists for $email, a reset link is on its way.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NavColors.of(context);

    return FScaffold(
      childPad: false,
      child: SafeArea(
        child: Center(
          // Scrollable so the on-screen keyboard can't overflow the layout.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandMark()),
                const SizedBox(height: 20),
                Text(
                  'Ranmap',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  'Travel together, stay in sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: c.mutedForeground),
                ),
                const SizedBox(height: 32),
                AuthTextField(
                  controller: _emailCtrl,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _passwordCtrl,
                  label: 'Password',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  FAlert(variant: .destructive, title: Text(_error!)),
                ],
                const SizedBox(height: 20),
                FButton(
                  size: .lg,
                  onPress: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: AppSpinner(color: Colors.white),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 4),
                FButton(
                  variant: .ghost,
                  onPress: _loading ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
                FButton(
                  variant: .ghost,
                  onPress: () => context.go('/sign-up'),
                  child: const Text('New here? Create an account'),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 420.ms, curve: Curves.easeOut)
                .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
          ),
        ),
      ),
    );
  }
}
