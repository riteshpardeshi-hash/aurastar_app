import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/utils/legal_links.dart';

/// "By continuing you agree to our Privacy Policy and Terms of Service."
/// with both names tappable, plus a disclosure that scores are shown on public
/// leaderboards (App Store guideline 5.1.2 — users must be told their data is
/// uploaded and shown publicly).
class LegalConsentText extends StatefulWidget {
  final Color accent;

  /// When [onChanged] is set the widget renders as an explicit-consent
  /// checkbox row (App Store guideline 1.2: users must actively agree to the
  /// terms before registering or logging in) instead of passive
  /// "by continuing" text.
  final bool checked;
  final ValueChanged<bool>? onChanged;

  const LegalConsentText({
    super.key,
    this.accent = const Color(0xFF7B2CBF),
    this.checked = false,
    this.onChanged,
  });

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
    final checkbox = widget.onChanged != null;

    final text = RichText(
      textAlign: checkbox ? TextAlign.start : TextAlign.center,
      text: TextSpan(
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
        children: checkbox
            ? [
                const TextSpan(text: 'I agree to the '),
                TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
                const TextSpan(text: ' and '),
                TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
                const TextSpan(
                    text: '. There is no tolerance for objectionable content '
                        'or abusive users. We\'ll ask before your display name, '
                        'avatar and score appear on public leaderboards.'),
              ]
            : [
                const TextSpan(text: 'By continuing you agree to our '),
                TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
                const TextSpan(text: ' and '),
                TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
                const TextSpan(
                    text: '. We\'ll ask before your display name, avatar and '
                        'score appear on public leaderboards.'),
              ],
      ),
    );
    if (!checkbox) return text;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: widget.checked,
            onChanged: (v) => widget.onChanged!(v ?? false),
            activeColor: widget.accent,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: text),
      ],
    );
  }
}
