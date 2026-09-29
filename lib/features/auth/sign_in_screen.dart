import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_tag.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/legal_consent_text.dart';
import '../../data/services/supabase_service.dart';
import 'social_auth.dart';
import 'widgets/auth_social.dart';
import 'widgets/brand_mark.dart';

/// Email / password sign-in, dressed in the brand surface and offering the same
/// Google / Apple providers as create-account.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
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
    final emailValidationError = emailError(email);
    if (emailValidationError != null) {
      setState(() => _error = emailValidationError);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.signInWithPassword(
        email: email,
        password: password,
      );
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
    if (emailError(email) != null) {
      setState(
        () => _error =
            'Enter your email address first, then tap "Forgot password?"',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.resetPasswordForEmail(
        email,
        redirectTo: kAuthRedirectUrl,
      );
      if (!mounted) return;
      showAppToast(
        context,
        'If an account exists for $email, a reset link is on its way.',
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens the provider's OAuth screen; the session arrives via the auth stream.
  Future<void> _social(OAuthProvider provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final launched = await signInWithProvider(provider);
      if (!launched && mounted) {
        showAppToast(context, 'Could not open the sign-in page');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.lg,
          bottom: BrandSpace.xl,
        ),
        children: [
          const _Hero()
              .animate()
              .fadeIn(duration: 420.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: BrandSpace.lg),
          _LabeledField(
            label: 'Email',
            child: BrandTextField(
              controller: _emailCtrl,
              hint: 'leo@ranmap.app',
              leadingIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => _clearError(),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          _LabeledField(
            label: 'Password',
            child: BrandTextField(
              controller: _passwordCtrl,
              hint: 'Your password',
              leadingIcon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _signIn(),
              onChanged: (_) => _clearError(),
              trailing: BrandFieldAction(
                icon: _obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                onTap: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _loading ? null : _resetPassword,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Text(
                  'Forgot password?',
                  style: BrandText.labelMd.copyWith(color: BrandColors.primary),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.sm),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.md),
          BrandPrimaryButton(
            label: 'Sign in',
            loading: _loading,
            onPressed: _signIn,
          ),
          const SizedBox(height: BrandSpace.lg),
          const AuthSocialDivider(),
          const SizedBox(height: BrandSpace.md),
          AuthSocialButtons(onProvider: _social, busy: _loading),
          const SizedBox(height: BrandSpace.lg),
          _CreateAccountPrompt(
            onTap: _loading ? null : () => context.push('/sign-up'),
          ),
          const SizedBox(height: BrandSpace.sm),
          const LegalConsentText(),
        ],
      ),
    );
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }
}

/// The brand hero: a glowing emblem, an eyebrow pill, and the welcome-back copy.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 104,
          width: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 100,
                width: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BrandColors.primaryContainer.withValues(alpha: 0.16),
                  boxShadow: [
                    BoxShadow(
                      color: BrandColors.primaryContainer.withValues(
                        alpha: 0.18,
                      ),
                      blurRadius: 48,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  borderRadius: BrandRadii.cardRadius,
                  color: BrandColors.surface,
                  boxShadow: BrandShadows.pod,
                ),
                child: Center(
                  child: const BrandMark(size: 64),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrandSpace.lg),
        BrandTag(
          emoji: '👋',
          label: 'Welcome back, road tripper',
          background: BrandColors.secondaryContainer,
          foreground: BrandColors.onSecondaryFixedVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Sign in to Ranmap',
          textAlign: TextAlign.center,
          style: BrandText.displayLgMobile.copyWith(
            color: BrandColors.textHeadline,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Text(
            'Your convoy’s waiting — pick up right where you left off.',
            textAlign: TextAlign.center,
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(
            label,
            style: BrandText.labelMd.copyWith(color: BrandColors.textHeadline),
          ),
        ),
        child,
      ],
    );
  }
}

class _CreateAccountPrompt extends StatelessWidget {
  const _CreateAccountPrompt({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          'New to Ranmap?',
          style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
        ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            'Create an account',
            style: BrandText.weight(
              BrandText.labelMd,
              700,
            ).copyWith(color: BrandColors.primary),
          ),
        ),
      ],
    );
  }
}
