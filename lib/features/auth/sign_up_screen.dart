import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../data/services/supabase_service.dart';
import 'widgets/auth_text_field.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final emailValidationError = emailError(email);
    if (emailValidationError != null) {
      setState(() => _error = emailValidationError);
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await SupabaseService.auth.signUp(email: email, password: password);
      // With email confirmation on, signUp returns no session and the router
      // stays put — tell the user to go verify instead of leaving them stuck.
      if (res.session == null && mounted) {
        setState(() => _info =
            'Account created. Check $email to confirm your address, then sign in.');
      }
      // If a session came back, the router redirect sends them to onboarding.
    } catch (e) {
      // Catches AuthException as well as network failures (offline,
      // timeout) so a bad connection during sign-up shows a message instead
      // of surfacing as an unhandled error.
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
      header: FHeader.nested(
        title: const Text('Create account'),
        prefixes: [
          FHeaderAction.back(onPress: () => context.go('/sign-in')),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Join Ranmap',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                'Create an account to start travelling together.',
                style: TextStyle(fontSize: 16, color: c.mutedForeground),
              ),
              const SizedBox(height: 28),
              AuthTextField(
                controller: _emailCtrl,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passwordCtrl,
                label: 'Password',
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _signUp(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                FAlert(variant: .destructive, title: Text(_error!)),
              ],
              if (_info != null) ...[
                const SizedBox(height: 14),
                FAlert(title: Text(_info!)),
              ],
              const SizedBox(height: 20),
              FButton(
                size: .lg,
                onPress: _loading ? null : _signUp,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: AppSpinner(color: Colors.white),
                      )
                    : const Text('Create account'),
              ),
              const SizedBox(height: 6),
              FButton(
                variant: .ghost,
                onPress: () => context.go('/sign-in'),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 420.ms, curve: Curves.easeOut)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}
