import 'package:flutter/foundation.dart' show debugPrint;
import 'package:url_launcher/url_launcher.dart';

class LegalDoc {
  final String title;
  final Uri uri;
  const LegalDoc(this.title, this.uri);
}

/// Legal pages hosted on the marketing website. The app only links to them —
/// the site is the single source of truth, so copy edits never need a release.
class LegalLinks {
  LegalLinks._();

  static const _base = 'https://www.auraarenaplay.com/legal';

  /// The Terms version the sign-in checkbox shows — recorded with the acceptance
  /// (`POST /profile/terms-acceptance`, backend ADR 129). Bump when the Terms change.
  static const termsVersion = '2026-10-14';

  /// Support contact shown in Settings (Apple 1.2 "publish a support email").
  static const supportEmail = 'info@onadsgroup.com';

  static final privacy = LegalDoc('Privacy Policy', Uri.parse('$_base/privacy.html'));
  static final terms = LegalDoc('Terms of Service', Uri.parse('$_base/terms.html'));

  /// Everything shown in Settings → Legal, in display order.
  static final all = <LegalDoc>[
    privacy,
    terms,
    LegalDoc('Community Guidelines', Uri.parse('$_base/community-guidelines.html')),
    LegalDoc('Copyright Policy', Uri.parse('$_base/copyright.html')),
    LegalDoc('Content & Music Policy', Uri.parse('$_base/content-music.html')),
    LegalDoc('Data Privacy Compliance', Uri.parse('$_base/data-privacy-compliance.html')),
    LegalDoc('Data Retention & Deletion', Uri.parse('$_base/retention-deletion.html')),
  ];

  /// Opens in an in-app browser tab, falling back to the external browser.
  /// Returns false if neither could open it.
  static Future<bool> open(LegalDoc doc) async {
    try {
      if (await launchUrl(doc.uri, mode: LaunchMode.inAppBrowserView)) {
        return true;
      }
      return await launchUrl(doc.uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('LegalLinks.open(${doc.uri}) failed: $e');
      return false;
    }
  }

  /// Opens the mail app addressed to [supportEmail]. False if no mail app could open it
  /// (the caller then shows the address so it can be copied).
  static Future<bool> emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=Aura%20Arena%20support',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('LegalLinks.emailSupport failed: $e');
      return false;
    }
  }
}
