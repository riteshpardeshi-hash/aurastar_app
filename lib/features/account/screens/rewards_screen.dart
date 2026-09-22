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
/// and admin Level-Up Offer vouchers (split into their own sections below by
/// [_VoucherCard]'s origin, not lumped together — a level-up voucher isn't a
/// leaderboard finish, even though both ride the same `/offer-vouchers` list).
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

  // A voucher is "level" if it carries levelAtGrant/level; everything else on
  // this list (rankAtGrant/rank, or neither) is a leaderboard-finish voucher
  // — see _VoucherCard's own _level/_rank getters for the same field names.
  List<Map<String, dynamic>> get _levelVouchers => _vouchers
      .where((v) => v['levelAtGrant'] != null || v['level'] != null)
      .toList();

  List<Map<String, dynamic>> get _leaderboardVouchers => _vouchers
      .where((v) => v['levelAtGrant'] == null && v['level'] == null)
      .toList();

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
                    _RewardGrid(
                      children: [
                        for (final r in _rewards)
                          _CouponRewardCard(reward: r, onClaimed: _load),
                      ],
                    ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'LEVEL-UP VOUCHERS',
                    subtitle: 'Won by reaching a new level',
                  ),
                  const SizedBox(height: 12),
                  if (_levelVouchers.isEmpty)
                    const _EmptyLine('Level up to win brand vouchers')
                  else
                    _RewardGrid(
                      children: [
                        for (final v in _levelVouchers) _VoucherCard(voucher: v),
                      ],
                    ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'LEADERBOARD VOUCHERS',
                    subtitle:
                        'Won by finishing near the top of a challenge leaderboard',
                  ),
                  const SizedBox(height: 12),
                  if (_leaderboardVouchers.isEmpty)
                    const _EmptyLine(
                        'Finish in a challenge’s top ranks to win brand vouchers')
                  else
                    _RewardGrid(
                      children: [
                        for (final v in _leaderboardVouchers)
                          _VoucherCard(voucher: v),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

/// Two-column grid: a [Wrap] rather than [GridView.count] because reward/
/// voucher cards have genuinely variable height (a claimed coupon's revealed
/// code + a redeem button vs. a bare aura-points line) — GridView.count would
/// either clip taller cards or waste space padding shorter ones to match a
/// fixed aspect ratio.
class _RewardGrid extends StatelessWidget {
  final List<Widget> children;
  const _RewardGrid({required this.children});

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - _gap) / 2;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
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

// Shared by both card types — no `intl` dependency in this app (see the
// same pattern in creator_gate_history_screen.dart).
String? _formatDate(String? iso) {
  if (iso == null) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}';
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
    // Server-resolved (reward.service.js#_attachRefTitles) — the Challenge
    // title or Offer name behind this reward, when refId/refModel point to
    // one. This is *why* the reward was earned, beyond the coarse `reason`
    // enum — two leaderboard_top rewards from two different days otherwise
    // render identically.
    final refTitle = widget.reward['refTitle'] as String?;
    final awardedAt =
        _formatDate(widget.reward['awardedAt'] as String? ?? widget.reward['createdAt'] as String?);

    final label = _reasonLabels[reason] ?? 'Reward';
    final isCoupon = rewardType == 'coupon_code';
    final icon = isCoupon ? Icons.card_giftcard_rounded : Icons.diamond_rounded;
    final amountLine = isCoupon
        ? (couponValue ?? 'Coupon reward')
        : (auraAmount != null ? '+$auraAmount Aura' : 'Aura reward');
    // Prefer the resolved reference (a real challenge/offer name) as the
    // "why" line; fall back to a date so even a context-free reward (e.g.
    // leaderboard_top, which has no single challenge behind it) is still
    // distinguishable from another instance of the same reason.
    final whyLine = refTitle ?? (awardedAt != null ? 'on $awardedAt' : null);

    // Only coupons have a trailing action/state: the revealed code, a Claim
    // button, or an Expired/Claimed pill. An aura_points reward is credited
    // automatically — nothing to act on, so no trailing widget.
    Widget? trailing;
    if (isCoupon && couponCode != null && couponCode.isNotEmpty) {
      trailing = _CodeChip(code: couponCode, expand: true);
    } else if (isCoupon && status == 'active') {
      trailing = SizedBox(
        width: double.infinity,
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
      trailing = Align(
        alignment: Alignment.centerLeft,
        child: _StatusPill(text: status == 'expired' ? 'Expired' : 'Claimed'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(amountLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11)),
          if (whyLine != null) ...[
            const SizedBox(height: 2),
            Text(whyLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 10.5)),
          ],
          if (trailing != null) ...[
            const SizedBox(height: 10),
            trailing,
          ],
        ],
      ),
    );
  }
}

// ── Leaderboard / level-up voucher card (GET /profile/offer-vouchers) ─────

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

  String? get _grantedOn => _formatDate(voucher['grantedAt'] as String? ?? voucher['createdAt'] as String?);

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
      width: double.infinity,
      height: 32,
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
    final grantedOn = _grantedOn;

    return Container(
      padding: const EdgeInsets.all(12),
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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: _accent, size: 18),
              ),
              const Spacer(),
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
          const SizedBox(height: 10),
          Text(_title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          // The reason line: exactly what earned this voucher (rank/level),
          // plus the coupon's own value, plus when it was granted — three
          // independent instances of the same origin (e.g. three separate
          // "Rank #1" days) now read as three distinct cards instead of
          // identical-looking duplicates.
          Text(
            [
              if (_originLabel != null) _originLabel,
              if (_value != null) _value,
            ].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          if (grantedOn != null) ...[
            const SizedBox(height: 2),
            Text('Won on $grantedOn',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 10.5)),
          ],
          if (code.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CodeChip(code: code, expand: true),
            if (isGranted && _redeemUrl != null) ...[
              const SizedBox(height: 8),
              _redeemButton(),
            ],
          ] else if (isGranted && _isCatalog && _redeemUrl != null) ...[
            // A code-less CATALOG deal — the link is the whole redemption.
            const SizedBox(height: 10),
            _redeemButton(),
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
        width: expand ? double.infinity : null,
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
