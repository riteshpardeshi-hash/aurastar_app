import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_colors.dart';

/// One-shot celebration shown right after scoring when the submission won one
/// or more coupons — the concatenation of `data.levelUpOffers` +
/// `data.leaderboardOffers` on `POST /challenges/{id}/submissions` (backend
/// coupon-integration contract, ADRs 082–084). The same coupons also live
/// permanently on RewardsScreen; this is just the moment-of-delight.
///
/// Each entry branches only on `sourcing`:
///  - `POOL`    — a real single-use code; show it big, copyable. `redeemUrl`
///                (if present) is the brand's own coupon page.
///  - `CATALOG` — a partner-network deal; the primary CTA opens `redeemUrl`
///                (always our own `/r/:grantId` redirect) in an in-app
///                browser. `code` may be present (show it too) or null.
Future<void> showCouponsSheet(
  BuildContext context,
  List<Map<String, dynamic>> coupons,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0E0C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _CouponsSheet(coupons: coupons),
  );
}

/// True when this coupon entry is a partner-catalog deal (shop at the
/// merchant) rather than a real voucher code from the offer's own pool.
///
/// `sourcing` is authoritative when present. The `/profile/offer-vouchers`
/// list does not currently return it, so fall back to the documented tell:
/// a CATALOG `redeemUrl` is always our own `/r/:grantId` redirect.
bool couponIsCatalog(Map<String, dynamic> c) {
  final sourcing = (c['sourcing'] as String?)?.toUpperCase();
  if (sourcing == 'CATALOG') return true;
  if (sourcing == 'POOL') return false;
  final url = (c['redeemUrl'] as String?) ?? '';
  return url.contains('/r/');
}

class _CouponsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> coupons;
  const _CouponsSheet({required this.coupons});

  @override
  Widget build(BuildContext context) {
    final many = coupons.length > 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.card_giftcard_rounded,
                color: AppColors.accent, size: 40),
            const SizedBox(height: 10),
            Text(
              many
                  ? 'You won ${coupons.length} coupons!'
                  : 'You won a coupon!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final c in coupons) _CouponCard(coupon: c),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            ),
            Text(
              'Also saved in Rewards',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final Map<String, dynamic> coupon;
  const _CouponCard({required this.coupon});

  String get _title {
    for (final k in ['voucherLabel', 'offerName']) {
      final v = (coupon[k] as String?)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return 'Coupon';
  }

  String? get _subtitle {
    final v = (coupon['reason'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? get _code {
    final v = (coupon['code'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? get _merchantName {
    final v = (coupon['merchantName'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? get _redeemUrl {
    final u = (coupon['redeemUrl'] as String?)?.trim();
    return (u == null || u.isEmpty) ? null : u;
  }

  String? get _expiryLabel {
    final raw = coupon['claimExpiresAt'] as String?;
    final when = raw == null ? null : DateTime.tryParse(raw);
    if (when == null) return null;
    final days = when.difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired';
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires in 1 day';
    return 'Expires in $days days';
  }

  // Both kinds open in an in-app browser (SFSafariViewController / Chrome
  // Custom Tab) so the user never leaves the app: CATALOG is our own
  // `/r/:grantId` redirect that 302s through the partner network to the
  // merchant; POOL is the brand's own coupon page.
  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    final isCatalog = couponIsCatalog(coupon);
    final code = _code;
    final redeemUrl = _redeemUrl;
    final expiry = _expiryLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141026),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          if (_subtitle != null) ...[
            const SizedBox(height: 3),
            Text(_subtitle!,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11, height: 1.35)),
          ],
          if (isCatalog) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: redeemUrl == null
                    ? null
                    : () => _open(redeemUrl),
                icon: const Icon(Icons.shopping_bag_rounded, size: 16),
                label: const Text('Shop now', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            if (code != null) ...[
              const SizedBox(height: 8),
              _CopyableCode(code: code),
            ],
            if (_merchantName != null) ...[
              const SizedBox(height: 6),
              Text('at ${_merchantName!}',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 11)),
            ],
          ] else ...[
            // POOL — a real voucher code.
            if (code != null) ...[
              const SizedBox(height: 12),
              _CopyableCode(code: code, big: true),
            ],
            if (redeemUrl != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: () => _open(redeemUrl),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentLight,
                    side: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Open offer',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
          if (expiry != null) ...[
            const SizedBox(height: 10),
            Text(expiry,
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _CopyableCode extends StatelessWidget {
  final String code;
  final bool big;
  const _CopyableCode({required this.code, this.big = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Code copied')));
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: big ? 12 : 8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                code,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.accentLight,
                  fontSize: big ? 16 : 12.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: big ? 1.5 : 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_rounded, size: 14, color: AppColors.accentLight),
          ],
        ),
      ),
    );
  }
}
