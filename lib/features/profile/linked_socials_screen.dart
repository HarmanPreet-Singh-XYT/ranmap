import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
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
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter the code you received');
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Phone number verified')));
      }
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
    final privateAsync = ref.watch(myPrivateProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Linked socials')),
      body: SafeArea(
        child: privateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(myPrivateProfileProvider)),
          data: (private) {
            _seed(private.phoneNumber, private.socials);
            final phoneMatchesStored =
                private.phoneNumber != null && _phoneCtrl.text.trim() == private.phoneNumber;
            final isVerified = phoneMatchesStored && private.phoneVerified;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Text('Mobile number', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    if (isVerified)
                      const Chip(
                        avatar: Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                        label: Text('Verified'),
                        backgroundColor: Color(0xFF3A9D5C),
                        labelStyle: TextStyle(color: Colors.white),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+15551234567',
                  ),
                  onChanged: (_) => setState(() => _codeSent = false),
                ),
                const SizedBox(height: 8),
                if (!isVerified) ...[
                  if (!_codeSent)
                    OutlinedButton.icon(
                      onPressed: _sendingCode ? null : _sendCode,
                      icon: _sendingCode
                          ? const SizedBox(
                              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sms_outlined),
                      label: Text(_sendingCode ? 'Sending…' : 'Send verification code'),
                    )
                  else ...[
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Verification code'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _checkingCode ? null : _checkCode,
                          child: _checkingCode
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Verify'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _sendingCode ? null : _sendCode,
                          child: const Text('Resend code'),
                        ),
                      ],
                    ),
                  ],
                  if (_codeError != null) ...[
                    const SizedBox(height: 8),
                    Text(_codeError!, style: const TextStyle(color: AppTheme.danger)),
                  ],
                ],
                const SizedBox(height: 24),
                Text('Socials', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._socials.map((s) {
                  final (id, label, hint) = s;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      controller: _socialCtrls[id],
                      decoration: InputDecoration(labelText: label, hintText: hint),
                    ),
                  );
                }),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _savingSocials ? null : _saveSocials,
                  child: _savingSocials
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
