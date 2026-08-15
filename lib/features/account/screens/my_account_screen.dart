import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/utils/error_message.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/aura_tier.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../challenges/widgets/achievement_card.dart';
import 'user_video_detail_screen.dart';
import 'all_videos_screen.dart';
import 'settings_screen.dart';
import 'saved_challenges_screen.dart';
import 'edit_profile_screen.dart';

// ── Achievement Cards Section ──────────────────────────────────────────────────

class _AchievementCardsSection extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  final String username;
  const _AchievementCardsSection({
    required this.cards,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MY ACHIEVEMENT CARDS', style: AppTextStyles.sectionHeader),
        const SizedBox(height: 14),
        SizedBox(
          // AchievementCardView is a fixed 268-wide card internally;
          // _AchievementMiniCard scales it down to _miniCardWidth via
          // FittedBox, so the row height follows the same aspect ratio
          // (810/1231) at that smaller width instead of the native 268.
          height: _AchievementMiniCard.width * 1231 / 810,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _AchievementMiniCard(
              cardData: cards[i],
              username: username,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The actual shareable "Flex Card" (AchievementCardView), shown directly
/// in the profile's horizontal achievement-card row. Tapping it opens the
/// same card full-size in a preview dialog with the share action.
class _AchievementMiniCard extends StatelessWidget {
  final Map<String, dynamic> cardData;
  final String username;

  const _AchievementMiniCard({
    required this.cardData,
    required this.username,
  });

  // AchievementCardView lays itself out at a fixed 268 width, so it's
  // scaled down to this width via FittedBox rather than resized directly.
  static const width = 150.0;

  @override
  Widget build(BuildContext context) {
    final challengeTitle = cardData['challengeTitle'] as String? ?? '';
    final challengeId = cardData['challengeId'] as String? ?? '';
    final auraPoints = (cardData['auraPoints'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => _showAchievementPreview(
        context,
        challengeTitle: challengeTitle,
        challengeId: challengeId,
        auraPoints: auraPoints,
      ),
      child: SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: AchievementCardView(
            challengeTitle: challengeTitle,
            challengeId: challengeId,
            auraPoints: auraPoints,
            username: username,
          ),
        ),
      ),
    );
  }

  void _showAchievementPreview(
    BuildContext context, {
    required String challengeTitle,
    required String challengeId,
    required int auraPoints,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => _AchievementCardPreviewDialog(
        challengeTitle: challengeTitle,
        challengeId: challengeId,
        auraPoints: auraPoints,
        username: username,
      ),
    );
  }
}

class _AchievementCardPreviewDialog extends StatefulWidget {
  final String challengeTitle;
  final String challengeId;
  final int auraPoints;
  final String username;

  const _AchievementCardPreviewDialog({
    required this.challengeTitle,
    required this.challengeId,
    required this.auraPoints,
    required this.username,
  });

  @override
  State<_AchievementCardPreviewDialog> createState() => _AchievementCardPreviewDialogState();
}

class _AchievementCardPreviewDialogState extends State<_AchievementCardPreviewDialog> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      Uint8List? bytes;
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }

      final link = '$kChallengeBaseUrl/${widget.challengeId}';
      final message =
          'I completed "${widget.challengeTitle}" on Aura and earned ${widget.auraPoints} Aura Points! 🏆\n\n'
          'Think you can beat me? Now it\'s your turn! 💪\n\n'
          '👉 $link';

      if (bytes != null) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: 'aura_achievement.png')],
          text: message,
        );
      } else {
        await Share.share(message);
      }
    } catch (_) {
      // share cancelled or failed
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: AchievementCardView(
                  challengeTitle: widget.challengeTitle,
                  challengeId: widget.challengeId,
                  auraPoints: widget.auraPoints,
                  username: widget.username,
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: _sharing ? null : _shareCard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF7B2CBF).withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1),
                    ],
                  ),
                  child: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.share_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Share Card', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── MyAccountScreen ────────────────────────────────────────────────────────────

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);
  static const _card = Color(0xFF0E0C1E);

  bool _loading = true;
  String? _error;
  String? _uid;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _savedChallenges = [];
  Map<String, dynamic>? _referral;
  Map<String, dynamic>? _referralStatsDetail;
  Map<String, dynamic>? _streak;
  List<Map<String, dynamic>> _rewards = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    // Only the first load (before we have a uid/profile) takes over the
    // whole screen with a spinner/error state; later refreshes (e.g. after
    // returning from EditProfileScreen) keep showing existing content.
    final isInitialLoad = _uid == null;
    if (isInitialLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = await ApiClient().userId;
      final results = await Future.wait<dynamic>([
        AuthApiService().getProfile(),
        AuthApiService().fetchMyVideos(limit: 10),
        AuthApiService().fetchSavedChallenges(limit: 4),
        AuthApiService().fetchReferralStats(),
        AuthApiService().fetchStreak(),
        AuthApiService().fetchReferralStatsDetail(),
        AuthApiService().fetchRewards(),
      ]);
      if (!mounted) return;
      setState(() {
        _uid = uid;
        _profile = results[0] as Map<String, dynamic>? ?? {};
        _videos = (results[1] as List).cast<Map<String, dynamic>>();
        _savedChallenges = (results[2] as List)
            .cast<Map<String, dynamic>>()
            .map(normaliseChallenge)
            .toList();
        _referral = results[3] as Map<String, dynamic>?;
        _streak = results[4] as Map<String, dynamic>?;
        _referralStatsDetail = results[5] as Map<String, dynamic>?;
        _rewards = (results[6] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (isInitialLoad) {
        setState(() {
          _error = humanizeError(e);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    }
  }

  Future<void> _reloadRewards() async {
    final rewards = await AuthApiService().fetchRewards();
    if (mounted) setState(() => _rewards = rewards);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static Map<String, dynamic> _normaliseSubmission(Map<String, dynamic> s) {
    final submissionId = s['_id'] as String? ?? s['id'] as String? ?? '';
    // `challenge` may come back as a populated sub-document (like `creatorId`
    // does on /challenges — see normaliseChallenge in challenges_service.dart)
    // or as a flat id/title pair; guessed defensively, same pattern as
    // elsewhere in this file, since /profile/videos has no per-item schema
    // in Swagger beyond SuccessEnvelope.
    final challenge = s['challengeId'];
    final challengeMap = challenge is Map<String, dynamic> ? challenge : null;
    // /profile/videos returns the Video document itself — its top-level
    // `status` (active/inactive) is the video's own lifecycle, unrelated to
    // AI scoring. The scoring result is nested under `submission` (confirmed
    // live 2026-08-05: video status "active" + processingStatus "completed"
    // while submission.status was "scored"/verdict "INVALID"). Fall back to
    // `s` itself for a video with no submission yet (still pending).
    final submission = s['submission'] as Map<String, dynamic>? ?? s;
    return {
      // The Submission and Video are distinct backend documents — DELETE
      // /videos/{id} needs the Video's own id. Fall back to the submission
      // id if the API ever omits videoId (delete would then 404 loudly
      // rather than silently corrupt the wrong document).
      'videoId': s['videoId'] as String? ?? submissionId,
      'videoUrl': s['videoUrl'] as String? ?? '',
      'thumbnailUrl': s['thumbnailUrl'] as String? ?? '',
      'status': submissionStatusFromApi(submission),
      // `/profile/videos`'s nested `submission` object omits `auraPoints`
      // outright (confirmed live 2026-08-05) — per openapi.yaml, auraPoints
      // is defined as "Raw aiScore stored on the submission record", so
      // aiScore is the correct fallback, not an approximation.
      'auraPoints': (submission['auraPoints'] as num?)?.toInt() ??
          (submission['aiScore'] as num?)?.toInt() ??
          0,
      'aiScore': submission['aiScore'],
      'aiReason': submission['feedback'] as String? ??
          submission['improvementTip'] as String? ??
          submission['aiReason'] as String? ??
          '',
      'reviewedByAI': submission['reviewedByAI'] as bool? ?? true,
      'challengeId': challengeMap?['_id'] as String? ??
          (challenge is String ? challenge : null) ??
          '',
      'challengeTitle': challengeMap?['title'] as String? ??
          s['challengeTitle'] as String? ??
          '',
    };
  }

  // ── Profile card ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard(BuildContext context) {
    final rawName = (_profile['displayName'] as String? ?? '').isNotEmpty
        ? _profile['displayName'] as String
        : _profile['name'] as String? ?? '';
    final name = rawName.isNotEmpty ? rawName : 'User';
    final username = _profile['profileName'] as String? ??
        _profile['username'] as String? ?? '';
    final gender = (_profile['gender'] as String? ?? '').trim();
    final city =
        (_profile['city'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final photoUrl = (_profile['avatar'] as String? ?? '').isNotEmpty
        ? _profile['avatar'] as String
        : _profile['profileImageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      ).then((result) {
        if (result is Map<String, dynamic>) {
          setState(() => _profile = {..._profile, ...result});
        }
        _loadAll();
      }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                AvatarWidget(
                  photoUrl: photoUrl,
                  fallbackText: name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  radius: 38,
                  backgroundColor: _accent.withValues(alpha: 0.20),
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: _card, width: 2),
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('@$username',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 4),
                        Text(city,
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 12)),
                      ],
                    ),
                  ],
                  if (gender.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 4),
                        Text(gender,
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _accent.withValues(alpha: 0.55), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.25),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFD4A8FF),
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Aura points card ─────────────────────────────────────────────────────────
  Widget _buildAuraPointsCard(int points, int level, String? tierName) {
    final tier = auraTierForName(tierName);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/level analysis banner.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'YOUR AURA POINTS',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.diamond,
                                  color: Color(0xFFD4A8FF), size: 28),
                              const SizedBox(width: 6),
                              Text(
                                _fmt(points),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 44,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            tier.color.withValues(alpha: 0.35),
                            tier.color.withValues(alpha: 0.08),
                          ],
                        ),
                        border: Border.all(
                            color: tier.color.withValues(alpha: 0.70),
                            width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: tier.color.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('LEVEL',
                              style: AppTextStyles.eyebrow.copyWith(color: AppColors.textMuted)),
                          Text(
                            '$level',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                          Text(
                            tier.name,
                            style: TextStyle(
                              color: tier.color,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Streak card ───────────────────────────────────────────────────────────────
  Widget _buildStreakCard() {
    if (_streak == null) return const SizedBox.shrink();
    final current = (_streak!['currentStreak'] as num?)?.toInt() ?? 0;
    final longest = (_streak!['longestStreak'] as num?)?.toInt() ?? 0;
    final completed = (_streak!['completedStreaks'] as num?)?.toInt() ?? 0;
    if (current == 0 && longest == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🔥', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DAILY STREAK',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 10, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  '$current day${current != 1 ? 's' : ''} in a row',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Best: $longest',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Completed: $completed',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Referral card ─────────────────────────────────────────────────────────────
  Widget _buildReferralCard(BuildContext context) {
    // GET /referrals's live response names this field `code`, not the
    // `referralCode` the OpenAPI spec documents (confirmed against the
    // running backend) — read both so a future spec-alignment fix on either
    // side doesn't silently re-break this.
    final referralCode = _referral?['code'] as String? ??
        _referral?['referralCode'] as String? ??
        '';
    if (referralCode.isEmpty) return const SizedBox.shrink();

    final link = 'https://aura-app-efae1.web.app/ref/$referralCode';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'REFER TO FRIENDS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Share your code. When your friend completes a challenge, you earn 50 Auras!',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Tap to copy Referral code',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 9),
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: referralCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Referral code copied!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.40),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        referralCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_referralStatsDetail != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _referralStatChip(
                  Icons.people_alt_rounded,
                  '${((_referralStatsDetail!['totalReferrals'] ?? _referralStatsDetail!['total']) as num?)?.toInt() ?? 0}',
                  'Referred',
                ),
                const SizedBox(width: 10),
                _referralStatChip(
                  Icons.diamond_rounded,
                  '${((_referralStatsDetail!['auraEarned'] ?? _referralStatsDetail!['totalAuraEarned'] ?? _referralStatsDetail!['earnedAura']) as num?)?.toInt() ?? 0}',
                  'Auras Earned',
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Share.share(
              '🎯 Join Aura Arena — copy viral challenges and earn real rewards!\n\n'
              'Use my referral code: $referralCode\n\n'
              '👉 $link\n\n'
              'Complete any challenge after signing up and I earn 50 bonus Auras! 🏆',
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.share_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'SHARE REFERRAL LINK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showReferralsSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: _accent.withValues(alpha: 0.25)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded,
                        color: Color(0xFFD4A8FF), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'VIEW REFERRED USERS',
                      style: TextStyle(
                        color: Color(0xFFD4A8FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _referralStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFD4A8FF), size: 15),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReferralsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _ReferralsSheet(),
    );
  }

  // ── My Videos grid ────────────────────────────────────────────────────────────
  Widget _buildMyVideosSection(BuildContext context) {
    final normalised = _videos.map(_normaliseSubmission).toList();
    final preview = normalised.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('MY VIDEOS', style: AppTextStyles.sectionHeader),
            const Spacer(),
            if (_videos.length > 4)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllVideosScreen()),
                ),
                child: const Text(
                  'VIEW ALL  ›',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (preview.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('No videos yet',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.65,
            children: List.generate(preview.length, (i) {
              final data = preview[i];
              final videoUrl = data['videoUrl'] as String;
              final thumbnailUrl = data['thumbnailUrl'] as String;
              final status = data['status'] as String;
              final auraPoints = data['auraPoints'] as int;
              final aiScore = data['aiScore'];
              final aiReason = data['aiReason'] as String;
              final reviewedByAI = data['reviewedByAI'] as bool;
              final videoId = data['videoId'] as String;

              final statusColor = _statusColor(status);
              final statusLabel = _statusLabel(status);

              return GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserVideoDetailScreen(
                        videoNumber: i + 1,
                        auraPoints: auraPoints,
                        videoUrl: videoUrl,
                        status: status,
                        aiScore: aiScore,
                        aiReason: aiReason,
                        reviewedByAI: reviewedByAI,
                        videoId: videoId,
                      ),
                    ),
                  );
                  if (result == 'deleted') _loadAll();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoThumbnailWidget(
                          videoUrl: videoUrl,
                          thumbnailUrl: thumbnailUrl,
                          fit: BoxFit.cover),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (status == 'approved')
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.diamond,
                                    color: Color(0xFFD4A8FF), size: 10),
                                const SizedBox(width: 3),
                                Text(
                                  '+$auraPoints',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':  return Colors.green;
      case 'rejected':  return Colors.red;
      case 'ai_error':  return Colors.orange;
      default:          return _accent;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':  return 'Approved';
      case 'rejected':  return 'Rejected';
      case 'ai_error':  return 'Review';
      default:          return 'Scoring...';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 40),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadAll,
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading || _uid == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF7B2CBF))),
      );
    }

    final totalRewards = (_profile['auraPoints'] as num?)?.toInt() ??
        (_profile['totalRewards'] as num?)?.toInt() ??
        0;
    // Server-computed and authoritative — do not recompute locally.
    final level = (_profile['level'] as num?)?.toInt() ?? 1;
    final tierName = _profile['tier'] as String?;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: SizedBox(
          height: 22,
          child: Image.asset(
            'assets/images/Aura arena.png',
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileCard(context),
              const SizedBox(height: 16),
              _buildAuraPointsCard(totalRewards, level, tierName),
              _buildStreakCard(),
              _RewardsSection(rewards: _rewards, onClaimed: _reloadRewards),
              const SizedBox(height: 8),
              _buildReferralCard(context),
              _AchievementCardsSection(
                // One flex card per approved challenge completion, not the
                // account-wide unlock badges from /profile/achievements
                // (that endpoint's shape — type/title/auraEarned — doesn't
                // even carry a challenge to share).
                cards: _videos
                    .map(_normaliseSubmission)
                    .where((v) => v['status'] == 'approved')
                    .toList(),
                username: _profile['profileName'] as String? ??
                    _profile['username'] as String? ?? '',
              ),
              _buildMyVideosSection(context),
              _SavedChallengesGrid(challenges: _savedChallenges),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rewards Section (real awarded rewards, GET /profile/rewards) ───────────────

class _RewardsSection extends StatelessWidget {
  final List<Map<String, dynamic>> rewards;
  final Future<void> Function() onClaimed;
  const _RewardsSection({required this.rewards, required this.onClaimed});

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MY REWARDS', style: AppTextStyles.sectionHeader),
        const SizedBox(height: 4),
        const Text(
          'Rewards earned from streaks, leaderboards, and challenges',
          style: TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
        const SizedBox(height: 14),
        for (final reward in rewards)
          _RewardCard(reward: reward, onClaimed: onClaimed),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RewardCard extends StatefulWidget {
  final Map<String, dynamic> reward;
  final Future<void> Function() onClaimed;
  const _RewardCard({required this.reward, required this.onClaimed});

  @override
  State<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<_RewardCard> {
  static const _accent = Color(0xFF7B2CBF);
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
    await AuthApiService().claimReward(id);
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
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isCoupon && status == 'claimed' && couponCode != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withValues(alpha: 0.4)),
              ),
              child: Text(couponCode,
                  style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            )
          else if (isCoupon && status == 'active')
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: (_claiming || id.isEmpty) ? null : () => _claim(id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _claiming
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Claim', style: TextStyle(fontSize: 12)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status == 'expired' ? 'Expired' : 'Claimed',
                style: const TextStyle(color: AppColors.textFaint, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Saved Challenges grid ─────────────────────────────────────────────────────

class _SavedChallengesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> challenges;
  const _SavedChallengesGrid({required this.challenges});

  @override
  Widget build(BuildContext context) {
    if (challenges.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Saved Challenges',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SavedChallengesScreen()),
              ),
              child: const Text(
                'VIEW ALL  ›',
                style: TextStyle(
                  color: Color(0xFF7B2CBF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: challenges.map((c) {
            final videoUrl = c['videoUrl'] as String? ?? '';
            final title    = c['title']    as String? ?? '';
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.78),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Referrals sheet ───────────────────────────────────────────────────────────

class _ReferralsSheet extends StatefulWidget {
  const _ReferralsSheet();

  @override
  State<_ReferralsSheet> createState() => _ReferralsSheetState();
}

class _ReferralsSheetState extends State<_ReferralsSheet> {
  List<Map<String, dynamic>> _referrals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AuthApiService().fetchReferralsList();
    if (!mounted) return;
    setState(() {
      _referrals = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.90,
      builder: (_, ctrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Referred Users',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF7B2CBF)))
                : _referrals.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                color: Colors.white24, size: 44),
                            SizedBox(height: 10),
                            Text('No referrals yet',
                                style: TextStyle(
                                    color: AppColors.textFaint, fontSize: 14)),
                            SizedBox(height: 4),
                            Text('Share your code to invite friends',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: ctrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: _referrals.length,
                        itemBuilder: (context, i) {
                          final r = _referrals[i];
                          final name = r['displayName'] as String? ??
                              r['name'] as String? ??
                              'User';
                          final username = r['username'] as String? ?? '';
                          final avatar = r['avatar'] as String? ?? '';
                          final aura = (r['auraAwarded'] as num? ??
                                  r['auraPoints'] as num?)
                              ?.toInt();
                          final joinedRaw = r['joinDate'] as String? ??
                              r['createdAt'] as String?;
                          String joined = '';
                          if (joinedRaw != null) {
                            try {
                              final dt =
                                  DateTime.parse(joinedRaw).toLocal();
                              joined =
                                  '${dt.day}/${dt.month}/${dt.year}';
                            } catch (_) {}
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0D1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                AvatarWidget(
                                  photoUrl: avatar,
                                  fallbackText: name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : 'U',
                                  radius: 20,
                                  backgroundColor:
                                      const Color(0xFF7B2CBF).withValues(alpha: 0.20),
                                  textStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)),
                                      if (username.isNotEmpty)
                                        Text('@$username',
                                            style: const TextStyle(
                                                color: AppColors.textFaint,
                                                fontSize: 11)),
                                      if (joined.isNotEmpty)
                                        Text('Joined $joined',
                                            style: const TextStyle(
                                                color: Colors.white24,
                                                fontSize: 10)),
                                    ],
                                  ),
                                ),
                                if (aura != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.diamond,
                                          color: Color(0xFFD4A8FF),
                                          size: 12),
                                      const SizedBox(width: 3),
                                      Text('+$aura',
                                          style: const TextStyle(
                                              color: Color(0xFFD4A8FF),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
