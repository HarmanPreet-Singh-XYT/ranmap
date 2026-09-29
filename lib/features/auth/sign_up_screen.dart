import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

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

/// Account creation ("Convoy Clean Modern"). Collects name / email / password,
/// shows live password-strength chips, and hands off to Supabase Auth. On
/// success the router redirects into onboarding.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _info;

  bool _hasLength = false;
  bool _hasNumber = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onPasswordChanged(String value) {
    final hasLength = value.length >= 8;
    final hasNumber = RegExp(r'\d').hasMatch(value);
    if (hasLength != _hasLength || hasNumber != _hasNumber) {
      setState(() {
        _hasLength = hasLength;
        _hasNumber = hasNumber;
      });
    }
  }

  Future<void> _signUp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final nameValidationError = nameError(name, label: 'Full name');
    if (nameValidationError != null) {
      setState(() => _error = nameValidationError);
      return;
    }
    final emailValidationError = emailError(email);
    if (emailValidationError != null) {
      setState(() => _error = emailValidationError);
      return;
    }
    if (!_hasLength || !_hasNumber) {
      setState(
        () => _error = 'Password needs at least 8 characters and 1 number',
      );
      return;
    }
    final passwordValidationError = passwordError(password);
    if (passwordValidationError != null) {
      setState(() => _error = passwordValidationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await SupabaseService.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );
      // With email confirmation on, signUp returns no session and the router
      // stays put — tell the user to verify instead of leaving them stuck.
      // Supabase returns no session for an already-registered address too, so
      // keep the copy neutral rather than asserting the account is new.
      if (res.session == null && mounted) {
        setState(
          () => _info =
              'If $email is a new address, check your inbox to confirm it, '
              'then sign in.',
        );
      }
      // With a session, the router redirect sends them to onboarding.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Create account',
        onBack: () => context.canPop() ? context.pop() : context.go('/welcome'),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.lg,
        ),
        children: [
          const _IntroHeader()
              .animate()
              .fadeIn(duration: 420.ms)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: BrandSpace.lg),
          _Field(
            label: 'Full Name',
            field: BrandTextField(
              controller: _nameCtrl,
              hint: 'e.g. Leo Vance',
              leadingIcon: Icons.badge_outlined,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              onChanged: (_) => _clearError(),
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          _Field(
            label: 'Email Address',
            field: BrandTextField(
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
          _Field(
            label: 'Password',
            field: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandTextField(
                  controller: _passwordCtrl,
                  hint: 'Create a strong password',
                  leadingIcon: Icons.lock_outline_rounded,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (v) {
                    _clearError();
                    _onPasswordChanged(v);
                  },
                  trailing: BrandFieldAction(
                    icon: _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    onTap: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StrengthChip(label: '8+ chars', met: _hasLength),
                    const SizedBox(width: 8),
                    _StrengthChip(label: 'At least 1 number', met: _hasNumber),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: BrandSpace.md),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          if (_info != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _info!, variant: BrandAlertVariant.info),
          ],
          const SizedBox(height: BrandSpace.md),
          BrandPrimaryButton(
            label: 'Create Account',
            loading: _loading,
            onPressed: _signUp,
          ),
          const SizedBox(height: BrandSpace.lg),
          const AuthSocialDivider(),
          const SizedBox(height: BrandSpace.md),
          AuthSocialButtons(onProvider: _social, busy: _loading),
          const SizedBox(height: BrandSpace.lg),
          _LogInPrompt(onTap: _loading ? null : () => context.push('/sign-in')),
          const SizedBox(height: BrandSpace.sm),
          const LegalConsentText(
            leadIn: "By continuing, you agree to RanMap's ",
          ),
        ],
      ),
    );
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
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
}

class _IntroHeader extends StatelessWidget {
  const _IntroHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BrandTag(
          emoji: '👋',
          label: 'Hey there, road tripper',
          background: BrandColors.secondaryContainer,
          foreground: BrandColors.onSecondaryFixedVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Create your account',
          textAlign: TextAlign.center,
          style: BrandText.displayLgMobile.copyWith(
            color: BrandColors.textHeadline,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            'Join your convoy crew with Supabase Auth & hit the open road.',
            textAlign: TextAlign.center,
            style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.field});

  final String label;
  final Widget field;

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
        field,
      ],
    );
  }
}

class _StrengthChip extends StatelessWidget {
  const _StrengthChip({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final bg = met ? BrandColors.secondaryFixed : BrandColors.surfaceContainer;
    final fg = met ? BrandColors.onSecondaryFixed : BrandColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BrandRadii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(label, style: BrandText.labelSm.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _LogInPrompt extends StatelessWidget {
  const _LogInPrompt({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          'Already have a RanMap account?',
          style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
        ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            'Log in',
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
