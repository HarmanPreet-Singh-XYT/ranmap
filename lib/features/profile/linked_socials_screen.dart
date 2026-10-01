import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_card.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../../core/widgets/error_retry.dart';
import 'profile_providers.dart';

const _socials = [
  ('instagram', 'Instagram', 'instagram.com/…'),
  ('x', 'X', 'x.com/…'),
  ('tiktok', 'TikTok', 'tiktok.com/@…'),
];

/// A social handle: letters, digits, dot, underscore or hyphen (the intersection
/// of the three platforms' rules). Rejects URLs, spaces, and stray text.
final _socialHandleRe = RegExp(r'^[A-Za-z0-9._-]+$');

String _socialLabel(String id) =>
    _socials.firstWhere((s) => s.$1 == id, orElse: () => (id, id, '')).$2;

class LinkedSocialsScreen extends ConsumerStatefulWidget {
  const LinkedSocialsScreen({super.key});

  @override
  ConsumerState<LinkedSocialsScreen> createState() =>
      _LinkedSocialsScreenState();
}

class _LinkedSocialsScreenState extends ConsumerState<LinkedSocialsScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final Map<String, TextEditingController> _socialCtrls = {
    for (final (id, _, _) in _socials) id: TextEditingController(),
  };
  bool _savingSocials = false;
  bool _sendingCode = false;
  bool _checkingCode = false;
  bool _codeSent = false;
  String? _error;
  String? _codeError;

  /// Signature of the server data last seeded into the controllers, so a
  /// re-fetch re-seeds only when something actually changed (and never clobbers
  /// what the user is typing).
  String? _seededSignature;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    for (final c in _socialCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromServer(String? phone, Map<String, String> socials) {
    final signature =
        '$phone|${socials.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    if (signature == _seededSignature) return;
    _seededSignature = signature;
    _phoneCtrl.text = phone ?? '';
    for (final (id, _, _) in _socials) {
      _socialCtrls[id]!.text = socials[id] ?? '';
    }
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    final phoneValidationError = phoneError(phone);
    if (phoneValidationError != null) {
      setState(() => _codeError = phoneValidationError);
      return;
    }

    setState(() {
      _sendingCode = true;
      _codeError = null;
    });
    try {
      await ref.read(phoneRepositoryProvider).sendCode(phone);
      setState(() => _codeSent = true);
    } catch (e) {
      setState(() => _codeError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _checkCode() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final codeValidationError = otpCodeError(code);
    if (codeValidationError != null) {
      setState(() => _codeError = codeValidationError);
      return;
    }

    setState(() {
      _checkingCode = true;
      _codeError = null;
    });
    try {
      await ref
          .read(phoneRepositoryProvider)
          .checkCode(phoneNumber: phone, code: code);
      ref.invalidate(myPrivateProfileProvider);
      _codeCtrl.clear();
      setState(() => _codeSent = false);
      if (mounted) showAppToast(context, 'Phone number verified');
    } catch (e) {
      setState(() => _codeError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _checkingCode = false);
    }
  }

  Future<void> _saveSocials() async {
    setState(() {
      _savingSocials = true;
      _error = null;
    });
    try {
      // Preserve any social keys we don't render, so saving the three known
      // handles doesn't silently drop the rest.
      final socials = <String, String>{
        ...?ref.read(myPrivateProfileProvider).valueOrNull?.socials,
      };
      for (final entry in _socialCtrls.entries) {
        final value = entry.value.text.trim();
        if (value.isEmpty) {
          socials.remove(entry.key);
        } else if (!_socialHandleRe.hasMatch(value)) {
          // Length is already capped by the field; reject non-handle text
          // (URLs/spaces) so the profile chip can't render garbage.
          setState(
            () => _error =
                'Enter a valid ${_socialLabel(entry.key)} handle — letters, '
                'numbers, dots, underscores and hyphens only.',
          );
          return;
        } else {
          socials[entry.key] = value;
        }
      }
      await ref.read(profileRepositoryProvider).updateMySocials(socials);
      ref.invalidate(myPrivateProfileProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingSocials = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final privateAsync = ref.watch(myPrivateProfileProvider);

    return BrandScaffold(
      header: BrandHeader(
        title: 'Linked socials',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: privateAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          onRetry: () => ref.invalidate(myPrivateProfileProvider),
        ),
        data: (private) {
          _syncFromServer(private.phoneNumber, private.socials);
          final phoneMatchesStored =
              private.phoneNumber != null &&
              _phoneCtrl.text.trim() == private.phoneNumber;
          final isVerified = phoneMatchesStored && private.phoneVerified;

          return ListView(
            padding: const EdgeInsets.only(
              top: BrandSpace.md,
              bottom: BrandSpace.xl,
            ),
            children: [
              BrandSectionHeader(
                icon: Icons.phone_iphone_rounded,
                title: 'Mobile number',
                trailing: isVerified
                    ? BrandPill(
                        label: 'Verified',
                        icon: Icons.verified_rounded,
                        background: BrandColors.secondaryFixed,
                        foreground: BrandColors.onSecondaryFixedVariant,
                        iconColor: BrandColors.primary,
                      )
                    : null,
              ),
              const SizedBox(height: BrandSpace.sm),
              BrandTextField(
                controller: _phoneCtrl,
                hint: '+15551234567',
                leadingIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                onChanged: (_) {
                  // Always rebuild: editing the number must immediately
                  // un-badge a previously verified number, not just when a
                  // code is pending.
                  setState(() {
                    if (_codeSent) _codeSent = false;
                  });
                },
              ),
              const SizedBox(height: BrandSpace.sm),
              if (!isVerified) ...[
                if (!_codeSent)
                  BrandSecondaryButton(
                    label: _sendingCode ? 'Sending…' : 'Send verification code',
                    leading: _sendingCode
                        ? const AppSpinner()
                        : const Icon(Icons.sms_outlined, size: 20),
                    onPressed: _sendingCode ? null : _sendCode,
                  )
                else ...[
                  BrandTextField(
                    controller: _codeCtrl,
                    hint: 'Verification code',
                    leadingIcon: Icons.password_rounded,
                    keyboardType: TextInputType.number,
                    maxLength: kOtpLength,
                  ),
                  const SizedBox(height: BrandSpace.sm),
                  Row(
                    children: [
                      BrandPrimaryButton(
                        label: 'Verify',
                        expand: false,
                        trailingIcon: null,
                        glow: false,
                        loading: _checkingCode,
                        onPressed: _checkingCode ? null : _checkCode,
                      ),
                      const SizedBox(width: BrandSpace.sm),
                      BrandSecondaryButton(
                        label: 'Resend code',
                        expand: false,
                        onPressed: _sendingCode ? null : _sendCode,
                      ),
                    ],
                  ),
                ],
                if (_codeError != null) ...[
                  const SizedBox(height: BrandSpace.gutterSm),
                  BrandAlert(message: _codeError!),
                ],
              ],
              const SizedBox(height: BrandSpace.lg),
              const BrandSectionHeader(
                icon: Icons.alternate_email_rounded,
                title: 'Socials',
              ),
              const SizedBox(height: BrandSpace.sm),
              ..._socials.map((s) {
                final (id, label, _) = s;
                return Padding(
                  padding: const EdgeInsets.only(bottom: BrandSpace.md),
                  child: BrandTextField(
                    controller: _socialCtrls[id]!,
                    hint: label,
                    leadingIcon: Icons.link_rounded,
                    maxLength: kSocialHandleMaxLength,
                  ),
                );
              }),
              if (_error != null) ...[
                const SizedBox(height: BrandSpace.sm),
                BrandAlert(message: _error!),
              ],
              const SizedBox(height: BrandSpace.lg),
              BrandPrimaryButton(
                label: 'Save',
                loading: _savingSocials,
                onPressed: _savingSocials ? null : _saveSocials,
              ),
            ],
          );
        },
      ),
    );
  }
}
