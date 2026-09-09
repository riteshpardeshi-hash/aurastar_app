import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/rewards_service.dart';
import '../../challenges/widgets/coupons_sheet.dart' show couponIsCatalog;
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/app_bottom_nav.dart';

/// The player's reward home. Two backend-distinct tracks (see
/// [RewardsService]): the `/profile/rewards` UserReward ledger — coupons and
/// aura bonuses awarded for streaks, admin grants, brand challenges and
/// milestones — and `/profile/offer-vouchers`, the brand Leaderboard Offer
/// vouchers won by finishing inside a challenge's top-`rankLimit` band.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = AppColors.accent;

  final _service = RewardsService();

  bool _loading = true;
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _vouchers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchRewards(),
      _service.fetchOfferVouchers(),
    ]);
    if (!mounted) return;
    setState(() {
      _rewards = results[0];
      _vouchers = results[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const AppBottomNav(activeTab: AppNavTab.profile),
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Rewards'),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: _loading && _rewards.isEmpty && _vouchers.isEmpty
            ? const _CenteredScroll(
                child: CircularProgressIndicator(color: _accent))
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _SectionHeader(
                    title: 'COUPONS & BONUSES',
                    subtitle:
                        'Earned from streaks, challenges and special rewards',
                  ),
                  const SizedBox(height: 12),
                  if (_rewards.isEmpty)
                    const _EmptyLine('No coupons or bonuses yet')
                  else
                    for (final r in _rewards)
                      _CouponRewardCard(reward: r, onClaimed: _load),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'LEADERBOARD VOUCHERS',
                    subtitle:
                        'Won by finishing near the top of a challenge leaderboard',
                  ),
                  const SizedBox(height: 12),
                  if (_vouchers.isEmpty)
                    const _EmptyLine(
                        'Finish in a challenge’s top ranks to win brand vouchers')
                  else
                    for (final v in _vouchers) _VoucherCard(voucher: v),
                ],
              ),
      ),
    );
  }
}

class _CenteredScroll extends StatelessWidget {
  final Widget child;
  const _CenteredScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.sectionHeader),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(text,
          style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
    );
  }
}

// ── Coupon / bonus card (GET /profile/rewards) ────────────────────────────

class _CouponRewardCard extends StatefulWidget {
  final Map<String, dynamic> reward;
  final Future<void> Function() onClaimed;
  const _CouponRewardCard({required this.reward, required this.onClaimed});

  @override
  State<_CouponRewardCard> createState() => _CouponRewardCardState();
}

class _CouponRewardCardState extends State<_CouponRewardCard> {
  static const _accent = AppColors.accent;
  bool _claiming = false;

  static const _reasonLabels = {
    'streak_completion': 'Streak Bonus',
    'leaderboard_top': 'Leaderboard Reward',
    'admin_manual': 'Bonus Reward',
    'brand_challenge': 'Brand Challenge Reward',
    'challenge_participant_target': 'Challenge Milestone Reward',
  };

  Future<void> _claim(String id) async {
    setState(() => _claiming = true);
    await RewardsService().claimReward(id);
    await widget.onClaimed();
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.reward['_id'] as String? ?? '';
    final rewardType = widget.reward['rewardType'] as String? ?? '';
    final reason = widget.reward['reason'] as String?;
    final status = widget.reward['status'] as String? ?? 'active';
    final auraAmount = (widget.reward['auraAmount'] as num?)?.toInt();
    final couponCode = widget.reward['couponCode'] as String?;
    final couponValue = widget.reward['couponValue'] as String?;

    final label = _reasonLabels[reason] ?? 'Reward';
    final isCoupon = rewardType == 'coupon_code';
    final icon = isCoupon ? Icons.card_giftcard_rounded : Icons.diamond_rounded;
    final subtitle = isCoupon
        ? (couponValue ?? 'Coupon reward')
        : (auraAmount != null ? '+$auraAmount Aura' : 'Aura reward');

    // Only coupons have a trailing action/state: the revealed code, a Claim
    // button, or an Expired/Claimed pill. An aura_points reward is credited
    // automatically — nothing to act on, so no trailing widget.
    Widget? trailing;
    if (isCoupon && couponCode != null && couponCode.isNotEmpty) {
      trailing = _CodeChip(code: couponCode);
    } else if (isCoupon && status == 'active') {
      trailing = SizedBox(
        height: 32,
        child: ElevatedButton(
          onPressed: (_claiming || id.isEmpty) ? null : () => _claim(id),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: _claiming
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Claim', style: TextStyle(fontSize: 12)),
        ),
      );
    } else if (isCoupon) {
      trailing = _StatusPill(text: status == 'expired' ? 'Expired' : 'Claimed');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }
}

// ── Leaderboard voucher card (GET /profile/offer-vouchers) ────────────────

class _VoucherCard extends StatelessWidget {
  final Map<String, dynamic> voucher;
  const _VoucherCard({required this.voucher});

  static const _accent = AppColors.accent;

  String get _title =>
      (voucher['offerName'] as String?)?.trim().isNotEmpty == true
          ? voucher['offerName'] as String
          : (voucher['voucherLabel'] as String?)?.trim().isNotEmpty == true
              ? voucher['voucherLabel'] as String
              : 'Leaderboard Voucher';

  String? get _value {
    final v = (voucher['voucherValue'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  int? get _rank =>
      (voucher['rankAtGrant'] as num?)?.toInt() ??
      (voucher['rank'] as num?)?.toInt();

  int? get _level =>
      (voucher['levelAtGrant'] as num?)?.toInt() ??
      (voucher['level'] as num?)?.toInt();

  /// What earned this coupon — a level-up or a leaderboard finish.
  String? get _originLabel {
    if (_level != null) return 'Level $_level reward';
    if (_rank != null) return 'Rank #$_rank';
    return null;
  }

  bool get _isCatalog => couponIsCatalog(voucher);

  String get _status =>
      (voucher['status'] as String?)?.toUpperCase() ?? 'GRANTED';

  String? get _merchantName {
    final v = (voucher['merchantName'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String? get _redeemUrl {
    final u = (voucher['redeemUrl'] as String?)?.trim();
    return (u == null || u.isEmpty) ? null : u;
  }

  String? get _expiryLabel {
    final raw = voucher['claimExpiresAt'] as String?;
    if (raw == null) return null;
    final when = DateTime.tryParse(raw);
    if (when == null) return null;
    final days = when.difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired';
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires tomorrow';
    return 'Expires in $days days';
  }

  // Both kinds open in an in-app browser so the user stays in the app: a
  // CATALOG `/r/:grantId` link 302s through the partner network to the
  // merchant; a POOL link is the brand's own coupon page.
  Future<void> _redeem() async {
    final url = _redeemUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  Widget _redeemButton() {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: _redeem,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(_isCatalog ? 'Shop now' : 'Redeem',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = (voucher['code'] as String?)?.trim() ?? '';
    final isGranted = _status == 'GRANTED';
    final expiry = _expiryLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted
              ? _accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (_value != null) _value,
                        if (_originLabel != null) _originLabel,
                      ].join('  ·  '),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                text: isGranted
                    ? 'Ready'
                    : _status == 'REDEEMED'
                        ? 'Redeemed'
                        : 'Expired',
                highlight: isGranted,
              ),
            ],
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _CodeChip(code: code, expand: true)),
                if (isGranted && _redeemUrl != null) ...[
                  const SizedBox(width: 8),
                  _redeemButton(),
                ],
              ],
            ),
          ] else if (isGranted && _isCatalog && _redeemUrl != null) ...[
            // A code-less CATALOG deal — the link is the whole redemption.
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: _redeemButton()),
          ],
          if (_isCatalog && _merchantName != null) ...[
            const SizedBox(height: 6),
            Text('at ${_merchantName!}',
                style:
                    const TextStyle(color: AppColors.textFaint, fontSize: 11)),
          ],
          if (expiry != null) ...[
            const SizedBox(height: 8),
            Text(expiry,
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────

class _CodeChip extends StatelessWidget {
  final String code;
  final bool expand;
  const _CodeChip({required this.code, this.expand = false});

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Expanded(
              flex: expand ? 1 : 0,
              child: Text(
                code,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.accentLight,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_rounded,
                size: 13, color: AppColors.accentLight),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final bool highlight;
  const _StatusPill({required this.text, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.accent.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: highlight
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: highlight ? AppColors.accentLight : AppColors.textFaint,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
