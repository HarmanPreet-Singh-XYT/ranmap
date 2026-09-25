import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/nav_palette.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/error_retry.dart';
import 'profile_providers.dart';

const _socials = [
  ('instagram', 'Instagram', 'instagram.com/…'),
  ('x', 'X', 'x.com/…'),
  ('tiktok', 'TikTok', 'tiktok.com/@…'),
];

class LinkedSocialsScreen extends ConsumerStatefulWidget {
  const LinkedSocialsScreen({super.key});

  @override
  ConsumerState<LinkedSocialsScreen> createState() => _LinkedSocialsScreenState();
}

class _LinkedSocialsScreenState extends ConsumerState<LinkedSocialsScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final Map<String, TextEditingController> _socialCtrls = {
    for (final (id, _, _) in _socials) id: TextEditingController(),
  };
  bool _seeded = false;
  bool _savingSocials = false;
  bool _sendingCode = false;
  bool _checkingCode = false;
  bool _codeSent = false;
  String? _error;
  String? _codeError;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    for (final c in _socialCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(String? phone, Map<String, String> socials) {
    if (_seeded) return;
    _seeded = true;
    _phoneCtrl.text = phone ?? '';
    socials.forEach((k, v) => _socialCtrls[k]?.text = v);
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) {
      setState(() => _codeError = 'Enter your number in international format, e.g. +15551234567');
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
      await ref.read(phoneRepositoryProvider).checkCode(phoneNumber: phone, code: code);
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
      final socials = <String, String>{
        for (final entry in _socialCtrls.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      };
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
    final c = NavColors.of(context);
    final privateAsync = ref.watch(myPrivateProfileProvider);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Linked socials'),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
      ),
      child: privateAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myPrivateProfileProvider)),
        data: (private) {
          _seed(private.phoneNumber, private.socials);
          final phoneMatchesStored =
              private.phoneNumber != null && _phoneCtrl.text.trim() == private.phoneNumber;
          final isVerified = phoneMatchesStored && private.phoneVerified;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Text('Mobile number', style: _section(c)),
                  const SizedBox(width: 10),
                  if (isVerified)
                    FBadge(variant: .secondary, child: const Text('Verified')),
                ],
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _phoneCtrl,
                  onChange: (_) {
                    if (_codeSent) setState(() => _codeSent = false);
                  },
                ),
                label: const Text('Phone number'),
                hint: '+15551234567',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              if (!isVerified) ...[
                if (!_codeSent)
                  FButton(
                    variant: .outline,
                    onPress: _sendingCode ? null : _sendCode,
                    prefix: _sendingCode ? const FCircularProgress(size: .sm) : const Icon(Icons.sms_outlined),
                    child: Text(_sendingCode ? 'Sending…' : 'Send verification code'),
                  )
                else ...[
                  FTextField(
                    control: FTextFieldControl.managed(controller: _codeCtrl),
                    label: const Text('Verification code'),
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FButton(
                        onPress: _checkingCode ? null : _checkCode,
                        child: _checkingCode
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: AppSpinner(color: Colors.white),
                              )
                            : const Text('Verify'),
                      ),
                      const SizedBox(width: 8),
                      FButton(
                        variant: .ghost,
                        onPress: _sendingCode ? null : _sendCode,
                        child: const Text('Resend code'),
                      ),
                    ],
                  ),
                ],
                if (_codeError != null) ...[
                  const SizedBox(height: 12),
                  FAlert(variant: .destructive, title: Text(_codeError!)),
                ],
              ],
              const SizedBox(height: 28),
              Text('Socials', style: _section(c)),
              const SizedBox(height: 12),
              ..._socials.map((s) {
                final (id, label, hint) = s;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FTextField(
                    control: FTextFieldControl.managed(controller: _socialCtrls[id]!),
                    label: Text(label),
                    hint: hint,
                    maxLength: kSocialHandleMaxLength,
                  ),
                );
              }),
              if (_error != null) ...[
                const SizedBox(height: 8),
                FAlert(variant: .destructive, title: Text(_error!)),
              ],
              const SizedBox(height: 24),
              FButton(
                size: .lg,
                onPress: _savingSocials ? null : _saveSocials,
                child: _savingSocials
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: AppSpinner(color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _section(NavColors c) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.foreground);
}
