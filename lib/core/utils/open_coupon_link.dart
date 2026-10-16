import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a coupon's `redeemUrl` (our own `/r/:grantId` redirect for CATALOG
/// deals, the brand's coupon page for POOL ones) in an in-app browser.
///
/// `launchUrl` reports failure by returning false or throwing; the old call
/// sites ignored both, so a link that couldn't open did nothing at all and the
/// user got no feedback. Falls back to the external browser, then tells the
/// user. Errors that happen *inside* the browser page (e.g. an affiliate
/// network rejecting the redirect) can't be detected from here — those are
/// fixed on the backend.
Future<void> openCouponLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  var opened = false;
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView) ||
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openCouponLink($url) failed: $e');
    }
  }
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text("Couldn't open this offer. Please try again later."),
      ),
    );
}
