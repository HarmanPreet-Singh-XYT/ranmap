import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/services/supabase_service.dart';

/// Which account credential is being changed.
enum CredentialKind {
  password,
  email;

  String get title => this == CredentialKind.password ? 'Change password' : 'Change email';
}

/// Updates the signed-in user's password or email via Supabase auth.
class ChangeCredentialScreen extends ConsumerStatefulWidget {
  const ChangeCredentialScreen({super.key, required this.kind});

  final CredentialKind kind;

  @override
  ConsumerState<ChangeCredentialScreen> createState() => _ChangeCredentialScreenState();
}

class _ChangeCredentialScreenState extends ConsumerState<ChangeCredentialScreen> {
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
      if (value.length < 6) {
        setState(() => _error = 'Password must be at least 6 characters');
        return;
      }
      if (value != _confirmCtrl.text) {
        setState(() => _error = 'Passwords do not match');
        return;
      }
    } else if (!value.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.auth.updateUser(
        _isPassword ? UserAttributes(password: value) : UserAttributes(email: value),
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
    final c = NavColors.of(context);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(widget.kind.title),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _isPassword
                ? 'Choose a new password for your account.'
                : 'We’ll send a confirmation link to the new address.',
            style: TextStyle(color: c.mutedForeground),
          ),
          const SizedBox(height: 20),
          if (_isPassword) ...[
            FTextField.password(
              control: FTextFieldControl.managed(controller: _valueCtrl),
              label: const Text('New password'),
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            FTextField.password(
              control: FTextFieldControl.managed(controller: _confirmCtrl),
              label: const Text('Confirm new password'),
              autofillHints: const [AutofillHints.newPassword],
              onSubmit: (_) => _save(),
            ),
          ] else
            FTextField.email(
              control: FTextFieldControl.managed(controller: _valueCtrl),
              label: const Text('New email'),
              onSubmit: (_) => _save(),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            FAlert(variant: .destructive, title: Text(_error!)),
          ],
          const SizedBox(height: 28),
          FButton(
            size: .lg,
            onPress: _saving ? null : _save,
            child: _saving ? const AppSpinner(color: Colors.white) : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
