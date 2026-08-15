import 'package:flutter/material.dart';
import '../../../core/models/aura_tier.dart';
import '../../../core/services/auth_api_service.dart';
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
  List<Map<String, dynamic>> _cards = [];
  List<Map<String, dynamic>> _pendingActions = [];
  int _followingCount = 0;
  int _auraBalance = 0;
  int _level = 1;
  String? _tierName;
  List<Map<String, dynamic>> _videos = [];

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
      AuthApiService().getProfile(),
      AuthApiService().fetchMyVideos(limit: 20),
    ]);
    if (!mounted) return;
    final overview = results[2] as Map<String, dynamic>;
    final profile = results[4] as Map<String, dynamic>?;
    setState(() {
      _page = results[0] as Map<String, dynamic>?;
      _summary = results[1] as Map<String, dynamic>;
      _cards = (overview['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _pendingActions =
          (overview['pendingActions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _followingCount = results[3] as int;
      _auraBalance = (profile?['auraPoints'] as num?)?.toInt() ?? 0;
      // Server-computed and authoritative — do not recompute locally.
      _level = (profile?['level'] as num?)?.toInt() ?? 1;
      _tierName = profile?['tier'] as String?;
      _videos = (results[5] as List)
          .cast<Map<String, dynamic>>()
          .map(_normaliseVideo)
          .toList();
      _loading = false;
    });
  }

  /// `GET /profile/videos` returns `verdict` (PASS/FAIL) rather than a plain
  /// `status` on some rows — same translation `my_account_screen.dart` does
  /// before display.
  static Map<String, dynamic> _normaliseVideo(Map<String, dynamic> v) {
    final verdict = v['verdict'] as String?;
    final rawStatus = v['status'] as String?;
    final status = verdict != null
        ? (verdict == 'PASS'
            ? 'approved'
            : verdict == 'FAIL'
                ? 'rejected'
                : 'ai_error')
        : rawStatus ?? 'pending';
    return {
      ...v,
      'status': status,
    };
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

    final tier = auraTierForName(_tierName);
    // Ordinal "what's next" — not derived from a guessed level threshold.
    final tierIdx = auraTiers.indexOf(tier);
    final nextTier = tierIdx + 1 < auraTiers.length ? auraTiers[tierIdx + 1] : null;

    final totalSubs = _videos.length;
    final approvedSubs = _videos.where((v) => v['status'] == 'approved').length;
    final approvalRate = totalSubs == 0 ? 0 : (approvedSubs / totalSubs * 100).round();
    final recentVideos = _videos.take(5).toList();

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
        SliverToBoxAdapter(
            child: _buildAuraProgress(_level, tier, nextTier, _auraBalance)),
        SliverToBoxAdapter(
            child: _buildStats(_auraBalance, totalSubs, approvedSubs, approvalRate)),
        if (_cards.isNotEmpty) SliverToBoxAdapter(child: _buildCards()),
        SliverToBoxAdapter(child: _buildQuickActions(context)),
        SliverToBoxAdapter(child: _buildRecentSubmissions(context, recentVideos)),
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

  Widget _buildAuraProgress(
    int level,
    AuraTier tier,
    AuraTier? nextTier,
    int totalRewards,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0820),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF7B2CBF), Color(0xFF9B4DFF)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Level $level',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SpaceGrotesk')),
              ),
              const SizedBox(width: 10),
              Text(tier.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'ClashDisplay')),
              const Spacer(),
              Text('$totalRewards Aura',
                  style: const TextStyle(
                      color: Color(0xFF9B4DFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SpaceGrotesk')),
            ],
          ),
          if (nextTier != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Next: ${nextTier.name}',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(
      int totalRewards, int totalSubs, int approvedSubs, int approvalRate) {
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
                  child: _statCard(
                      'Total Aura', '$totalRewards', Icons.auto_awesome,
                      const Color(0xFF7B2CBF))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Submissions', '$totalSubs',
                      Icons.video_collection, Colors.blue)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statCard('Approved', '$approvedSubs',
                      Icons.check_circle_outline, Colors.green)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Approval Rate', '$approvalRate%',
                      Icons.trending_up_rounded, Colors.orange)),
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

  Widget _buildRecentSubmissions(
      BuildContext context, List<Map<String, dynamic>> recentVideos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Recent Submissions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
        ),
        if (recentVideos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.video_camera_back_outlined,
                      color: Colors.white24, size: 36),
                  SizedBox(height: 10),
                  Text('No submissions yet',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Take a challenge to earn Aura points',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          ...recentVideos.map((v) => _buildSubmissionRow(context, v)),
      ],
    );
  }

  Widget _buildSubmissionRow(BuildContext context, Map<String, dynamic> v) {
    final challengeTitle = pickString(v, ['challengeTitle', 'challengeName'], fallback: 'Challenge');
    final status = v['status'] as String? ?? 'pending';
    final aiScore = v['aiScore'] as num?;
    final auraPoints = (v['auraPoints'] as num?)?.toInt() ?? 0;
    final createdAtRaw = pickString(v, ['createdAt']);
    final createdAt = createdAtRaw.isEmpty ? null : DateTime.tryParse(createdAtRaw);
    final timeStr = createdAt != null ? _timeAgo(createdAt) : '';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(challengeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(timeStr,
                          style: const TextStyle(
                              color: AppColors.textFaint, fontSize: 10)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (aiScore != null)
                Text('${aiScore.toInt()}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        fontFamily: 'SpaceGrotesk')),
              if (status == 'approved' && auraPoints > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Color(0xFF9B4DFF), size: 12),
                    const SizedBox(width: 2),
                    Text('+$auraPoints',
                        style: const TextStyle(
                            color: Color(0xFF9B4DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
