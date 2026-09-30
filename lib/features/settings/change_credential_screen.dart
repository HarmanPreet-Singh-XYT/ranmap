import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../data/services/supabase_service.dart';

/// Which account credential is being changed.
enum CredentialKind {
  password,
  email;

  String get title =>
      this == CredentialKind.password ? 'Change password' : 'Change email';
}

/// Updates the signed-in user's password or email via Supabase auth.
class ChangeCredentialScreen extends ConsumerStatefulWidget {
  const ChangeCredentialScreen({super.key, required this.kind});

  final CredentialKind kind;

  @override
  ConsumerState<ChangeCredentialScreen> createState() =>
      _ChangeCredentialScreenState();
}

class _ChangeCredentialScreenState
    extends ConsumerState<ChangeCredentialScreen> {
  final _valueCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isPassword => widget.kind == CredentialKind.password;

  @override
  void dispose() {
    _valueCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _valueCtrl.text.trim();
    if (_isPassword) {
      // Match the sign-up rule (length + at least one digit) so a password
      // change can't weaken the account below what sign-up allows.
      final passwordValidationError = passwordError(value);
      if (passwordValidationError != null) {
        setState(() => _error = passwordValidationError);
        return;
      }
      if (value != _confirmCtrl.text) {
        setState(() => _error = 'Passwords do not match');
        return;
      }
    } else if (emailError(value) != null) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.updateUser(
        _isPassword
            ? UserAttributes(password: value)
            : UserAttributes(email: value),
      );
      if (!mounted) return;
      showAppToast(
        context,
        _isPassword
            ? 'Password updated.'
            : 'Check your inbox to confirm the new email address.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: widget.kind.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.lg,
          bottom: BrandSpace.xl,
        ),
        children: [
          Text(
            _isPassword
                ? 'Choose a new password for your account.'
                : 'We’ll send a confirmation link to the new address.',
            style: BrandText.bodyMd.copyWith(color: BrandColors.textMuted),
          ),
          const SizedBox(height: BrandSpace.lg),
          if (_isPassword) ...[
            BrandTextField(
              controller: _valueCtrl,
              hint: 'New password',
              leadingIcon: Icons.lock_outline_rounded,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: BrandSpace.md),
            BrandTextField(
              controller: _confirmCtrl,
              hint: 'Confirm new password',
              leadingIcon: Icons.lock_outline_rounded,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _save(),
            ),
          ] else
            BrandTextField(
              controller: _valueCtrl,
              hint: 'New email',
              leadingIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _save(),
            ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Save',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
