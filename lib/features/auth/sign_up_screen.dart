import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
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
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _emailCtrl,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _passwordCtrl,
                label: 'Password',
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _signUp(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              ],
              if (_info != null) ...[
                const SizedBox(height: 12),
                Text(_info!, style: const TextStyle(color: AppTheme.notice)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _signUp,
                child: _loading
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Sign up'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/sign-in'),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
