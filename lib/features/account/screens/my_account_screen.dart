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
  final String? city;
  const _AchievementCardsSection({
    required this.cards,
    required this.username,
    this.city,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MY ACHIEVEMENT CARDS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _AchievementMiniCard(
              cardData: cards[i],
              featured: i == 0,
              username: username,
              city: city,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Compact tile shown in the profile's horizontal achievement-card row.
/// Tapping it opens the full shareable "Flex Card" (AchievementCardView) in
/// a preview dialog so the capture happens while it's genuinely on-screen.
class _AchievementMiniCard extends StatelessWidget {
  final Map<String, dynamic> cardData;
  final bool featured;
  final String username;
  final String? city;

  const _AchievementMiniCard({
    required this.cardData,
    required this.featured,
    required this.username,
    this.city,
  });

  static const _accent = Color(0xFF7B2CBF);

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
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: featured ? _accent.withValues(alpha: 0.16) : const Color(0xFF17162A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: featured ? _accent.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.08),
            width: featured ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AURA',
              style: TextStyle(
                color: featured ? _accent : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'CHALLENGE COMPLETED',
              style: TextStyle(
                color: featured ? Colors.white70 : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Text(
              challengeTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '+$auraPoints',
              style: TextStyle(
                color: featured ? Colors.white : Colors.white70,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            Text(
              'AURA POINTS',
              style: TextStyle(
                color: featured ? _accent : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
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
        city: city,
      ),
    );
  }
}

class _AchievementCardPreviewDialog extends StatefulWidget {
  final String challengeTitle;
  final String challengeId;
  final int auraPoints;
  final String username;
  final String? city;

  const _AchievementCardPreviewDialog({
    required this.challengeTitle,
    required this.challengeId,
    required this.auraPoints,
    required this.username,
    this.city,
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
                  city: widget.city,
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
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _savedChallenges = [];
  Map<String, dynamic>? _referral;
  Map<String, dynamic>? _streak;

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
        AuthApiService().fetchAchievements(),
        AuthApiService().fetchSavedChallenges(limit: 4),
        AuthApiService().fetchReferralStats(),
        AuthApiService().fetchStreak(),
      ]);
      if (!mounted) return;
      setState(() {
        _uid = uid;
        _profile = results[0] as Map<String, dynamic>? ?? {};
        _videos = (results[1] as List).cast<Map<String, dynamic>>();
        _achievements = (results[2] as List).cast<Map<String, dynamic>>();
        _savedChallenges = (results[3] as List)
            .cast<Map<String, dynamic>>()
            .map(normaliseChallenge)
            .toList();
        _referral = results[4] as Map<String, dynamic>?;
        _streak = results[5] as Map<String, dynamic>?;
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

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static Map<String, dynamic> _normaliseSubmission(Map<String, dynamic> s) {
    final submissionId = s['_id'] as String? ?? s['id'] as String? ?? '';
    return {
      // The Submission and Video are distinct backend documents — DELETE
      // /videos/{id} needs the Video's own id. Fall back to the submission
      // id if the API ever omits videoId (delete would then 404 loudly
      // rather than silently corrupt the wrong document).
      'videoId': s['videoId'] as String? ?? submissionId,
      'videoUrl': s['videoUrl'] as String? ?? '',
      'status': submissionStatusFromApi(s),
      'auraPoints': (s['auraPoints'] as num?)?.toInt() ?? 0,
      'aiScore': s['aiScore'],
      'aiReason': s['feedback'] as String? ?? s['aiReason'] as String? ?? '',
      'reviewedByAI': s['reviewedByAI'] as bool? ?? true,
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
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: Colors.white38, size: 14),
                        const SizedBox(width: 4),
                        Text(city,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
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
                                color: Colors.white38, fontSize: 12)),
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
                                color: Colors.white70,
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
                          const Text('LEVEL',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 9,
                                  letterSpacing: 1)),
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
                      color: Colors.white54, fontSize: 10, letterSpacing: 1),
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
                    color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Completed: $completed',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Referral card ─────────────────────────────────────────────────────────────
  Widget _buildReferralCard(BuildContext context) {
    final referralCode = _referral?['referralCode'] as String? ?? '';
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
                          color: Colors.white54, fontSize: 11, height: 1.4),
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
                    style: TextStyle(color: Colors.white38, fontSize: 9),
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
            const Text(
              'MY VIDEOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
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
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
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
                          videoUrl: videoUrl, fit: BoxFit.cover),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileCard(context),
            const SizedBox(height: 16),
            _buildAuraPointsCard(totalRewards, level, tierName),
            _buildStreakCard(),
            _RewardsSection(level: level),
            const SizedBox(height: 8),
            _buildReferralCard(context),
            _AchievementCardsSection(
              cards: _achievements,
              username: _profile['profileName'] as String? ??
                  _profile['username'] as String? ?? '',
              city: (_profile['city'] as Map<String, dynamic>?)?['name']
                  as String?,
            ),
            _buildMyVideosSection(context),
            _SavedChallengesGrid(challenges: _savedChallenges),
            const SizedBox(height: 12),
            const _OffersRow(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Rewards Section (horizontal tier cards) ────────────────────────────────────

class _RewardsSection extends StatelessWidget {
  final int level;
  const _RewardsSection({required this.level});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MY REWARDS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Earn more Aura to unlock higher tier rewards',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: auraTiers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final tier = auraTiers[i];
              final isUnlocked = level >= tier.minLevel;
              return _HorizontalTierCard(tier: tier, isUnlocked: isUnlocked);
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HorizontalTierCard extends StatelessWidget {
  final AuraTier tier;
  final bool isUnlocked;
  const _HorizontalTierCard({required this.tier, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 115,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUnlocked
            ? tier.color.withValues(alpha: 0.14)
            : const Color(0xFF12102A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? tier.color.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.09),
          width: isUnlocked ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            color: isUnlocked ? tier.color : Colors.white24,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            tier.name.toUpperCase(),
            style: TextStyle(
              color: isUnlocked ? tier.color : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isUnlocked ? 'Unlocked' : 'Lv ${tier.minLevel}',
            style: TextStyle(
              color: isUnlocked ? Colors.white38 : Colors.white24,
              fontSize: 10,
            ),
          ),
          if (isUnlocked && tier.rewards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${tier.rewards.length} reward${tier.rewards.length != 1 ? 's' : ''}',
              style: TextStyle(
                color: tier.color.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${tier.rewards.first.brand} — ${tier.rewards.first.title}',
              style: const TextStyle(color: Colors.white38, fontSize: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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

// ── Offers row (API-backed) ───────────────────────────────────────────────────

class _OffersRow extends StatefulWidget {
  const _OffersRow();

  @override
  State<_OffersRow> createState() => _OffersRowState();
}

class _OffersRowState extends State<_OffersRow> {
  bool _hasOffers = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rewards = await AuthApiService().fetchRewards();
      if (!mounted) return;
      setState(() {
        _hasOffers = rewards.isNotEmpty;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOffers = _loaded && _hasOffers;

    return GestureDetector(
      onTap: () => _showOffersSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hasOffers
              ? const Color(0xFFF59E0B).withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasOffers
                ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hasOffers
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasOffers
                    ? Icons.local_offer_rounded
                    : Icons.local_offer_outlined,
                color: hasOffers ? const Color(0xFFF59E0B) : Colors.white38,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Offers',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    hasOffers
                        ? 'Tap to view your rewards & codes'
                        : 'Complete challenges to unlock brand offers',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  void _showOffersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _OffersSheet(),
    ).then((_) => _load());
  }
}

class _OffersSheet extends StatefulWidget {
  const _OffersSheet();

  @override
  State<_OffersSheet> createState() => _OffersSheetState();
}

class _OffersSheetState extends State<_OffersSheet> {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _claimed = [];
  bool _loading = true;
  final Set<String> _claiming = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AuthApiService().fetchRewards(status: 'active'),
      AuthApiService().fetchRewards(status: 'claimed'),
    ]);
    if (!mounted) return;
    setState(() {
      _active = (results[0] as List).cast<Map<String, dynamic>>();
      _claimed = (results[1] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _claim(String id) async {
    setState(() => _claiming.add(id));
    try {
      await AuthApiService().claimReward(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF1A0A2E),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _claiming.remove(id));
    }
  }

  String _formatReason(String? reason) {
    switch (reason) {
      case 'streak_completion':
        return 'Streak Reward';
      case 'leaderboard_top':
        return 'Leaderboard Reward';
      case 'admin_manual':
        return 'Admin Gift';
      case 'brand_challenge':
        return 'Brand Challenge';
      case 'challenge_participant_target':
        return 'Challenge Target';
      default:
        return 'Reward';
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildRewardTile(Map<String, dynamic> r, {bool canClaim = false}) {
    final id = r['_id'] as String? ?? '';
    final couponCode = r['couponCode'] as String? ?? '';
    final couponValue = r['couponValue'] as String? ?? '';
    final reason = r['reason'] as String?;
    final awardedAt = _formatDate(r['awardedAt'] as String?);
    final claimedAt = _formatDate(r['claimedAt'] as String?);
    final isClaiming = _claiming.contains(id);
    const gold = Color(0xFFF59E0B);
    const green = Color(0xFF22C55E);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatReason(reason),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                    if (couponValue.isNotEmpty)
                      Text(
                        couponValue,
                        style: TextStyle(
                            color: gold.withValues(alpha: 0.80),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              if (canClaim)
                GestureDetector(
                  onTap: isClaiming ? null : () => _claim(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B2CBF).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF7B2CBF)
                              .withValues(alpha: 0.60)),
                    ),
                    child: isClaiming
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Color(0xFF7B2CBF), strokeWidth: 2),
                          )
                        : const Text('CLAIM',
                            style: TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                  ),
                ),
            ],
          ),
          if (couponCode.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: couponCode));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Code "$couponCode" copied!'),
                  backgroundColor: const Color(0xFF1A0A2E),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: green.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number_rounded,
                        color: green, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(couponCode,
                          style: const TextStyle(
                              color: green,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2)),
                    ),
                    const Icon(Icons.copy_rounded,
                        color: Colors.white24, size: 13),
                  ],
                ),
              ),
            ),
          ],
          if (claimedAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Claimed $claimedAt',
                  style:
                      const TextStyle(color: Colors.white24, fontSize: 10)),
            )
          else if (awardedAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Awarded $awardedAt',
                  style:
                      const TextStyle(color: Colors.white24, fontSize: 10)),
            ),
        ],
      ),
    );
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
            child: Text('My Rewards & Offers',
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
                : (_active.isEmpty && _claimed.isEmpty)
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_offer_outlined,
                                color: Colors.white24, size: 44),
                            SizedBox(height: 10),
                            Text('No rewards yet',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 14)),
                            SizedBox(height: 4),
                            Text('Complete challenges to earn rewards',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView(
                        controller: ctrl,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        children: [
                          if (_active.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text('Available to Claim',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5)),
                            ),
                            ..._active.map(
                                (r) => _buildRewardTile(r, canClaim: true)),
                            const SizedBox(height: 8),
                          ],
                          if (_claimed.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text('Claimed',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5)),
                            ),
                            ..._claimed.map((r) => _buildRewardTile(r)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
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
                                    color: Colors.white38, fontSize: 14)),
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
                                                color: Colors.white38,
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
