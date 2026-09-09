import 'package:flutter/material.dart';
import '../../../core/services/creator_account_service.dart';
import '../../../core/services/creator_challenges_service.dart' show pickInt, pickString;
import '../../../core/services/creator_dashboard_service.dart';
import '../../../core/services/creator_page_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../challenges/screens/all_general_challenges_screen.dart';
import 'creator_challenge_status_screen.dart';
import 'creator_challenges_screen.dart';
import 'creator_follow_list_screen.dart';
import 'creator_insights_screen.dart';
import 'creator_settings_screen.dart';

class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key});

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  bool _loading = true;
  Map<String, dynamic>? _page;
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _overviewSummary = {};
  List<Map<String, dynamic>> _cards = [];
  List<Map<String, dynamic>> _pendingActions = [];
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      CreatorPageService().fetchOwnPage(),
      CreatorPageService().fetchDashboardSummary(),
      CreatorDashboardService().fetchOverview(),
      CreatorAccountService().fetchFollowingCount(),
    ]);
    if (!mounted) return;
    final overview = results[2] as Map<String, dynamic>;
    setState(() {
      _page = results[0] as Map<String, dynamic>?;
      _summary = results[1] as Map<String, dynamic>;
      // Creator-scoped totals across this creator's own challenges (the
      // backend reuses these from GET /creator/insights). Deliberately NOT
      // the account's personal Aura balance or player submission history —
      // those belong to the player profile (My Account), not the creator
      // dashboard. See ADR 009.
      _overviewSummary =
          (overview['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      _cards = (overview['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _pendingActions =
          (overview['pendingActions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _followingCount = results[3] as int;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B2CBF)))
            : RefreshIndicator(
                color: const Color(0xFF7B2CBF),
                onRefresh: _load,
                child: _buildBody(context),
              ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final page = _page ?? {};
    final displayName = pickString(page, ['displayName'], fallback: 'Creator');
    final username = pickString(page, ['username']);
    final bio = pickString(page, ['bio']);
    final profileImage = pickString(page, ['profileImage']);

    final followers = pickInt(_summary, ['followers']);
    final canUploadChallenge = _summary['canUploadChallenge'] as bool? ?? true;
    final profileComplete = _summary['profileComplete'] as bool? ?? true;
    final creatorPageLive = _summary['creatorPageLive'] as bool? ?? true;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 8, top: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatorSettingsScreen())),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: _buildHeader(context, displayName, username, bio, profileImage,
                followers, _followingCount)),
        if (!canUploadChallenge)
          SliverToBoxAdapter(
              child: _buildStatusBanner(profileComplete, creatorPageLive)),
        if (_pendingActions.isNotEmpty)
          SliverToBoxAdapter(child: _buildPendingActions(context)),
        SliverToBoxAdapter(child: _buildStats()),
        if (_cards.isNotEmpty) SliverToBoxAdapter(child: _buildCards()),
        SliverToBoxAdapter(child: _buildQuickActions(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String name,
    String username,
    String bio,
    String profileImage,
    int followerCount,
    int followingCount,
  ) {
    final displayName = name.isNotEmpty ? name : 'Creator';
    final initial = displayName[0].toUpperCase();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A2E), Color(0xFF2D1B4E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: profileImage.isEmpty
                      ? const LinearGradient(
                          colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  image: profileImage.isNotEmpty
                      ? DecorationImage(image: NetworkImage(profileImage), fit: BoxFit.cover)
                      : null,
                  border: Border.all(
                      color: const Color(0xFF9B4DFF).withValues(alpha: 0.6), width: 2),
                ),
                child: profileImage.isEmpty
                    ? Center(
                        child: Text(initial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay')),
                    if (username.isNotEmpty)
                      Text('@$username',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF7B2CBF).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Color(0xFF9B4DFF), size: 14),
                    SizedBox(width: 4),
                    Text('Creator',
                        style: TextStyle(
                            color: Color(0xFF9B4DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _followStat(context, '$followerCount', 'Followers', FollowListMode.followers),
              const SizedBox(width: 24),
              _followStat(context, '$followingCount', 'Following', FollowListMode.following),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(bool profileComplete, bool creatorPageLive) {
    final message = !profileComplete
        ? 'Complete your creator profile to start uploading challenges.'
        : !creatorPageLive
            ? 'Your creator page isn\'t live yet — uploads are paused until it is.'
            : 'Uploading is currently paused for your account.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _followStat(BuildContext context, String value, String label, FollowListMode mode) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CreatorFollowListScreen(mode: mode))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SpaceGrotesk')),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  /// Creator-scoped stats only — challenges this creator has published and the
  /// engagement they've drawn. The account's personal Aura balance, level, and
  /// player submission history are intentionally absent: those are player-side
  /// figures that carried over when the account was promoted to `creator`, and
  /// they belong on My Account, not here. See ADR 009.
  Widget _buildStats() {
    final challenges = pickInt(_overviewSummary, ['totalChallenges']);
    final live = pickInt(_overviewSummary, ['liveChallenges']);
    final participants = pickInt(_overviewSummary, ['totalParticipants']);
    final stars = pickInt(_overviewSummary, ['totalStars']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Stats',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _statCard('Challenges', '$challenges',
                      Icons.video_collection, Colors.blue)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Live', '$live',
                      Icons.podcasts_rounded, Colors.green)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statCard('Participants', '$participants',
                      Icons.groups_rounded, const Color(0xFF7B2CBF))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Stars', '$stars',
                      Icons.star_rounded, Colors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  static const _cardIcons = {
    'total_participants': Icons.groups_rounded,
    'total_views': Icons.visibility_rounded,
    'total_likes': Icons.favorite_rounded,
    'total_shares': Icons.share_rounded,
    'aura_earned': Icons.auto_awesome,
  };

  /// Cards are a dynamic, backend-computed list (`key`/`title`/`value`) so
  /// the backend can add new ones without a client change — render off
  /// `title`/`value` generically, only using `key` to pick an icon (with a
  /// sane fallback for keys not in [_cardIcons]).
  Widget _buildCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Growth',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _cards.map((card) {
              final key = card['key'] as String? ?? '';
              final title = card['title'] as String? ?? '';
              final value = card['value'];
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 16 * 2 - 10) / 2,
                child: _statCard(
                  title,
                  value is num ? _formatCardValue(value) : '$value',
                  _cardIcons[key] ?? Icons.insights_rounded,
                  const Color(0xFF7B2CBF),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _formatCardValue(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  Widget _buildPendingActions(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF7B2CBF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Needs Your Attention (${_pendingActions.length})',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ..._pendingActions.map((a) => _pendingActionRow(context, a)),
        ],
      ),
    );
  }

  Widget _pendingActionRow(BuildContext context, Map<String, dynamic> action) {
    final type = action['type'] as String? ?? '';
    final message = action['message'] as String? ?? '';
    final challengeId = action['challengeId'] as String?;
    final icon = switch (type) {
      'challenge_pending_review' => Icons.hourglass_top_rounded,
      'challenge_changes_requested' => Icons.rate_review_outlined,
      'challenge_rejected' => Icons.cancel_outlined,
      'gate_unlocked_unread' => Icons.lock_open_rounded,
      'profile_not_verified' => Icons.verified_outlined,
      'profile_incomplete' => Icons.person_outline_rounded,
      _ => Icons.info_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: challengeId == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CreatorChallengeStatusScreen(challengeId: challengeId)))
                .then((_) => _load()),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF9B4DFF), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
            ),
            if (challengeId != null)
              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SpaceGrotesk')),
          const SizedBox(height: 2),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  label: 'My Challenges',
                  icon: Icons.video_collection_rounded,
                  gradient: const [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreatorChallengesScreen())),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  label: 'Insights',
                  icon: Icons.bar_chart_rounded,
                  gradient: const [Color(0xFF1E3A5F), Color(0xFF2563EB)],
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreatorInsightsScreen())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _actionBtn(
            label: 'Browse Challenges',
            icon: Icons.flash_on_rounded,
            gradient: const [Color(0xFF7B2CBF), Color(0xFF9B4DFF)],
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AllGeneralChallengesScreen())),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
    );
  }

}
