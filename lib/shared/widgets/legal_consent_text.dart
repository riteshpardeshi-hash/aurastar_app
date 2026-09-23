import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/utils/legal_links.dart';

/// "By continuing you agree to our Privacy Policy and Terms of Service."
/// with both names tappable.
class LegalConsentText extends StatefulWidget {
  final Color accent;
  const LegalConsentText({super.key, this.accent = const Color(0xFF7B2CBF)});

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final TapGestureRecognizer _privacy;
  late final TapGestureRecognizer _terms;

  @override
  void initState() {
    super.initState();
    _privacy = TapGestureRecognizer()..onTap = () => _open(LegalLinks.privacy);
    _terms = TapGestureRecognizer()..onTap = () => _open(LegalLinks.terms);
  }

  @override
  void dispose() {
    _privacy.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _open(LegalDoc doc) async {
    final ok = await LegalLinks.open(doc);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the page. Try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(
      color: widget.accent,
      decoration: TextDecoration.underline,
      decorationColor: widget.accent,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
