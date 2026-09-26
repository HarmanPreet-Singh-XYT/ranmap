import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/brand_palette.dart';
import '../../core/theme/brand_typography.dart';
import '../../core/util/error_text.dart';
import '../../core/util/validation.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/brand/brand_alert.dart';
import '../../core/widgets/brand/brand_buttons.dart';
import '../../core/widgets/brand/brand_pod.dart';
import '../../core/widgets/brand/brand_scaffold.dart';
import '../../core/widgets/brand/brand_step_indicator.dart';
import '../../core/widgets/brand/brand_tag.dart';
import '../../core/widgets/brand/brand_text_field.dart';
import '../profile/profile_providers.dart';

/// Step 3 of onboarding: SMS OTP verification via the backend's Twilio Verify
/// wrapper. Optionally seeded with an already-known [phone]; otherwise the
/// user enters one first.
class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key, this.phone});

  final String? phone;

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  static const _resendSeconds = 45;

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _sending = false;
  bool _checking = false;
  bool _codeSent = false;
  String? _error;

  Timer? _countdown;
  int _secondsLeft = _resendSeconds;

  String get _phone => _phoneCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    if (widget.phone != null && widget.phone!.isNotEmpty) {
      _phoneCtrl.text = widget.phone!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdown?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft <= 1) {
          timer.cancel();
          _secondsLeft = 0;
        } else {
          _secondsLeft--;
        }
      });
    });
  }

  Future<void> _sendCode() async {
    final phone = _phone;
    final phoneValidationError = phoneError(phone);
    if (phoneValidationError != null) {
      setState(() => _error = phoneValidationError);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(phoneRepositoryProvider).sendCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _codeCtrl.clear();
      });
      _startCountdown();
      _codeFocus.requestFocus();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final codeValidationError = otpCodeError(_codeCtrl.text.trim());
    if (codeValidationError != null) {
      setState(() => _error = codeValidationError);
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await ref
          .read(phoneRepositoryProvider)
          .checkCode(phoneNumber: _phone, code: _codeCtrl.text.trim());
      ref.invalidate(myPrivateProfileProvider);
      if (!mounted) return;
      showAppToast(context, 'Phone number verified');
      context.go('/');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      header: BrandHeader(
        title: 'Verify phone',
        showBack: false,
        onSkip: () => context.go('/'),
        showAvatar: true,
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: BrandSpace.md,
          bottom: BrandSpace.lg,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const BrandStepPill(label: 'Step 3 of 3'),
              BrandTag(
                icon: Icons.verified_user_rounded,
                label: 'RanMap Secure',
                background: BrandColors.surfaceContainerLow,
                iconColor: BrandColors.primary,
              ),
            ],
          ),
          const SizedBox(height: BrandSpace.lg),
          const _VerificationHeader(),
          const SizedBox(height: BrandSpace.md),
          if (!_codeSent)
            _PhoneEntry(
              controller: _phoneCtrl,
              sending: _sending,
              onSend: _sendCode,
              onChanged: () {
                if (_error != null) setState(() => _error = null);
              },
            )
          else
            _OtpEntry(
              phone: _phone,
              controller: _codeCtrl,
              focusNode: _codeFocus,
              onEdit: () {
                _countdown?.cancel();
                setState(() {
                  _codeSent = false;
                  _secondsLeft = _resendSeconds;
                });
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: BrandSpace.md),
            BrandAlert(message: _error!),
          ],
          if (_codeSent) ...[
            const SizedBox(height: BrandSpace.md),
            _ResendCard(
              secondsLeft: _secondsLeft,
              onResend: _sending ? null : _sendCode,
            ),
          ],
          const SizedBox(height: BrandSpace.md),
          const _TrustPill(),
          const SizedBox(height: BrandSpace.md),
          const _FeatureTeasers(),
          const SizedBox(height: BrandSpace.lg),
          BrandPrimaryButton(
            label: 'Complete & Enter RanMap',
            loading: _checking,
            onPressed: _codeSent ? _verify : null,
          ),
          const SizedBox(height: 12),
          Text(
            'Carrier SMS rates may apply. Your number is used only for real-time convoy coordination.',
            textAlign: TextAlign.center,
            style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _VerificationHeader extends StatelessWidget {
  const _VerificationHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 88,
          width: 88,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 80,
                width: 80,
                decoration: BoxDecoration(
                  color: BrandColors.surfaceContainerLow,
                  borderRadius: BrandRadii.cardRadius,
                  boxShadow: BrandShadows.ambient,
                ),
                child: Center(
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: BrandColors.accentPeach.withValues(alpha: 0.6),
                      borderRadius: BrandRadii.miniRadius,
                    ),
                    child: Icon(
                      Icons.phonelink_lock_rounded,
                      size: 28,
                      color: BrandColors.tertiary,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  height: 32,
                  width: 32,
                  decoration: BoxDecoration(
                    color: BrandColors.primaryContainer,
                    shape: BoxShape.circle,
                    boxShadow: BrandShadows.subtle,
                  ),
                  child: Icon(
                    Icons.sms_rounded,
                    size: 16,
                    color: BrandColors.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrandSpace.md),
        Text(
          'Verify your phone number',
          textAlign: TextAlign.center,
          style: BrandText.headlineLg.copyWith(color: BrandColors.textHeadline),
        ),
        const SizedBox(height: 6),
        Text(
          'We’ll text a $kOtpLength-digit code via Twilio Verify to keep your convoy secure.',
          textAlign: TextAlign.center,
          style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
        ),
      ],
    );
  }
}

class _PhoneEntry extends StatelessWidget {
  const _PhoneEntry({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BrandTextField(
          controller: controller,
          hint: '+15551234567',
          leadingIcon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          radius: BrandRadii.pill,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSend(),
        ),
        const SizedBox(height: BrandSpace.md),
        BrandPrimaryButton(
          label: 'Send code',
          trailingIcon: Icons.sms_rounded,
          loading: sending,
          onPressed: onSend,
        ),
      ],
    );
  }
}

class _OtpEntry extends StatelessWidget {
  const _OtpEntry({
    required this.phone,
    required this.controller,
    required this.focusNode,
    required this.onEdit,
  });

  final String phone;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              'Code sent to',
              style: BrandText.bodyMd.copyWith(color: BrandColors.textBody),
            ),
            Text(
              phone,
              style: BrandText.titleSm.copyWith(
                color: BrandColors.textHeadline,
              ),
            ),
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Edit',
                    style: BrandText.labelMd.copyWith(
                      color: BrandColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: BrandColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: BrandSpace.md),
        _OtpBoxes(controller: controller, focusNode: focusNode),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 13,
              color: BrandColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              'Tap a box to enter the code',
              style: BrandText.labelSm.copyWith(color: BrandColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Six OTP cells driven by a single (visually hidden) text field laid over the
/// row, so paste / autofill / one-shot SMS autofill all work.
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  static const _length = kOtpLength;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.focusNode.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final focused = widget.focusNode.hasFocus;

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < _length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _cell(i, code, focused)),
            ],
          ],
        ),
        // Invisible capture field overlaying the cells.
        Positioned.fill(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: _length,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(int index, String code, bool focused) {
    final filled = index < code.length;
    final isActive = focused && index == code.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 58,
      decoration: BoxDecoration(
        color: isActive ? BrandColors.surface : BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.miniRadius,
        border: isActive
            ? Border.all(color: BrandColors.primaryContainer, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
        boxShadow: BrandShadows.subtle,
      ),
      alignment: Alignment.center,
      child: filled
          ? Text(
              code[index],
              style: BrandText.headlineMd.copyWith(
                color: BrandColors.textHeadline,
              ),
            )
          : isActive
          ? Container(
              height: 24,
              width: 2,
              decoration: BoxDecoration(
                color: BrandColors.primaryContainer,
                borderRadius: BrandRadii.pill,
              ),
            )
          : Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                color: BrandColors.outlineVariant.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

class _ResendCard extends StatelessWidget {
  const _ResendCard({required this.secondsLeft, required this.onResend});

  final int secondsLeft;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final canResend = secondsLeft == 0 && onResend != null;
    final secs = secondsLeft < 10 ? '0$secondsLeft' : '$secondsLeft';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandSpace.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: BrandColors.canvas,
        borderRadius: BrandRadii.cardRadius,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: BrandColors.textMuted,
              ),
              const SizedBox(width: 8),
              if (secondsLeft > 0)
                Text(
                  'Resend code in ',
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
              if (secondsLeft > 0)
                Text(
                  '0:$secs',
                  style: BrandText.labelMd.copyWith(
                    color: BrandColors.textHeadline,
                  ),
                )
              else
                Text(
                  'Didn’t get the code?',
                  style: BrandText.bodySm.copyWith(
                    color: BrandColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: canResend ? onResend : null,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    'Resend SMS',
                    style: BrandText.labelSm.copyWith(
                      color: canResend
                          ? BrandColors.primary
                          : BrandColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: BrandColors.surfaceContainerLow,
        borderRadius: BrandRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 16, color: BrandColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Twilio Secure Verification • Server-verified token',
              style: BrandText.labelSm.copyWith(color: BrandColors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTeasers extends StatelessWidget {
  const _FeatureTeasers();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Teaser(
            icon: Icons.podcasts_rounded,
            title: 'Live PTT Mesh Sync',
            body: 'Zero-latency crew check-ins',
            tint: BrandColors.accentSky,
          ),
        ),
        SizedBox(width: BrandSpace.gutterSm),
        Expanded(
          child: _Teaser(
            icon: Icons.sos_rounded,
            title: 'Emergency SOS Ping',
            body: 'Satellite & SMS relay ready',
            tint: BrandColors.accentPeach,
          ),
        ),
      ],
    );
  }
}

class _Teaser extends StatelessWidget {
  const _Teaser({
    required this.icon,
    required this.title,
    required this.body,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return BrandPod(
      color: tint.withValues(alpha: 0.3),
      radius: BrandRadii.cardRadius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(
              color: BrandColors.surface,
              borderRadius: BrandRadii.miniRadius,
              boxShadow: BrandShadows.subtle,
            ),
            child: Icon(icon, size: 16, color: BrandColors.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: BrandText.labelSm.copyWith(color: BrandColors.textHeadline),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: BrandText.bodySm.copyWith(color: BrandColors.textBody),
          ),
        ],
      ),
    );
  }
}
