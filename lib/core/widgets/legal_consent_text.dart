import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/env.dart';
import '../theme/brand_palette.dart';
import '../theme/brand_typography.dart';
import 'app_toast.dart';

/// The "By continuing you agree to …" line, with tappable Terms of Service and
/// Privacy Policy links when those URLs are configured (`TERMS_URL` /
/// `PRIVACY_URL`). Falls back to plain text when they aren't, rather than
/// pointing at a URL that may not exist.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({
    super.key,
    this.leadIn = "By continuing you agree to Ranmap's ",
    this.connector = ' & ',
    this.textAlign = TextAlign.center,
  });

  final String leadIn;
  final String connector;
  final TextAlign textAlign;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      if (mounted) showAppToast(context, 'Could not open that link', error: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final base = BrandText.labelSm.copyWith(color: BrandColors.textMuted);
    final link = BrandText.labelSm.copyWith(
      color: BrandColors.primary,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.leadIn, style: base),
          TextSpan(
            text: 'Terms of Service',
            style: link,
            recognizer: _tap(Env.termsUrl),
          ),
          TextSpan(text: widget.connector, style: base),
          TextSpan(
            text: 'Privacy Policy',
            style: link,
            recognizer: _tap(Env.privacyUrl),
          ),
          TextSpan(text: '.', style: base),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
