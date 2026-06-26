import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/challenges_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/aura_tier.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../challenges/widgets/achievement_card.dart';
import 'user_video_detail_screen.dart';
import 'settings_screen.dart';
import 'saved_challenges_screen.dart';
import 'edit_profile_screen.dart';

// ── Achievement Cards Section ──────────────────────────────────────────────────

class _AchievementCardsSection extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  const _AchievementCardsSection({required this.cards});

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
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _AchievementCardTile(cardData: cards[i]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AchievementCardTile extends StatefulWidget {
  final Map<String, dynamic> cardData;
  const _AchievementCardTile({required this.cardData});

  @override
  State<_AchievementCardTile> createState() => _AchievementCardTileState();
}

class _AchievementCardTileState extends State<_AchievementCardTile> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      Uint8List? bytes;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }

      final challengeId = widget.cardData['challengeId'] as String? ?? '';
      final challengeTitle =
          widget.cardData['challengeTitle'] as String? ?? '';
      final auraPoints =
          (widget.cardData['auraPoints'] as num?)?.toInt() ?? 0;
      final link = '$kChallengeBaseUrl/$challengeId';
      final message =
          'I completed "$challengeTitle" on Aura and earned $auraPoints Aura Points! 🏆\n\n'
          'Think you can beat me? Now it\'s your turn! 💪\n\n'
          '👉 $link';

      if (bytes != null) {
        await Share.shareXFiles(
          [
            XFile.fromData(bytes,
                mimeType: 'image/png', name: 'aura_achievement.png')
          ],
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
    final challengeTitle =
        widget.cardData['challengeTitle'] as String? ?? '';
    final challengeId = widget.cardData['challengeId'] as String? ?? '';
    final auraPoints =
        (widget.cardData['auraPoints'] as num?)?.toInt() ?? 0;
    final username = widget.cardData['username'] as String? ?? '';
    final city = widget.cardData['city'] as String?;
    final cityRank = (widget.cardData['cityRank'] as num?)?.toInt();

    return GestureDetector(
      onTap: _shareCard,
      child: Stack(
        children: [
          SizedBox(
            width: 196,
            height: 220,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: _cardKey,
                child: AchievementCardView(
                  challengeTitle: challengeTitle,
                  challengeId: challengeId,
                  auraPoints: auraPoints,
                  username: username,
                  city: city,
                  cityRank: cityRank,
                ),
              ),
            ),
          ),
          if (_sharing)
            Positioned(
              width: 196,
              height: 220,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF7B2CBF), strokeWidth: 2),
                ),
              ),
            ),
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share_rounded, color: Colors.white, size: 11),
                  SizedBox(width: 4),
                  Text('Share',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
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
  static const int _xpPerLevel = 1300;
  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);
  static const _card = Color(0xFF0E0C1E);

  bool _loading = true;
  String? _uid;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _savedChallenges = [];
  Map<String, dynamic>? _referral;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final uid = await ApiClient().userId;
    final results = await Future.wait<dynamic>([
      AuthApiService().getProfile(),
      AuthApiService().fetchMyVideos(limit: 10),
      AuthApiService().fetchAchievements(),
      AuthApiService().fetchSavedChallenges(limit: 4),
      AuthApiService().fetchReferralStats(),
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
      _loading = false;
    });
  }

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;
  int _xpInLevel(int pts) => pts % _xpPerLevel;
  double _progress(int pts) => (pts % _xpPerLevel) / _xpPerLevel;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  static Map<String, dynamic> _normaliseSubmission(Map<String, dynamic> s) {
    final verdict = s['verdict'] as String?;
    final rawStatus = s['status'] as String?;
    final status = verdict != null
        ? (verdict == 'PASS'
            ? 'approved'
            : verdict == 'FAIL'
                ? 'rejected'
                : 'ai_error')
        : rawStatus ?? 'pending';
    return {
      'submissionId': s['_id'] as String? ?? s['id'] as String? ?? '',
      'videoUrl': s['videoUrl'] as String? ?? '',
      'status': status,
      'auraPoints': (s['auraPoints'] as num?)?.toInt() ?? 0,
      'aiScore': s['aiScore'],
      'aiReason': s['feedback'] as String? ?? s['aiReason'] as String? ?? '',
      'reviewedByAI': s['reviewedByAI'] as bool? ?? true,
    };
  }

  // ── Profile card ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard(BuildContext context) {
    final name = _profile['displayName'] as String? ?? 'User';
    final username = _profile['username'] as String? ?? '';
    final gender = (_profile['gender'] as String? ?? '').trim();
    final photoUrl = _profile['avatar'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      ).then((_) => _loadAll()),
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
                CircleAvatar(
                  radius: 38,
                  backgroundColor: _accent.withValues(alpha: 0.20),
                  backgroundImage: photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
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
  Widget _buildAuraPointsCard(int points) {
    final level = _level(points);
    final progress = _progress(points);
    final xpToNext = _xpPerLevel - _xpInLevel(points);
    final tier = auraTierForLevel(level);

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
                const SizedBox(height: 18),
                Text(
                  '$xpToNext XP to Next Level',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 5,
                          width: constraints.maxWidth * progress,
                          child: Image.asset('assets/images/bar.png',
                              fit: BoxFit.fill),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10),
                  ),
                ),
              ],
            ),
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
        ],
      ),
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
                onTap: () {},
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
              final submissionId = data['submissionId'] as String;

              final statusColor = _statusColor(status);
              final statusLabel = _statusLabel(status);

              return GestureDetector(
                onTap: () => Navigator.push(
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
                      submissionId: submissionId,
                    ),
                  ),
                ),
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
    if (_loading || _uid == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF7B2CBF))),
      );
    }

    final totalRewards =
        (_profile['auraPoints'] as num?)?.toInt() ?? 0;

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
            _buildAuraPointsCard(totalRewards),
            _RewardsSection(level: _level(totalRewards)),
            const SizedBox(height: 8),
            _buildReferralCard(context),
            _AchievementCardsSection(cards: _achievements),
            _buildMyVideosSection(context),
            _SavedChallengesGrid(challenges: _savedChallenges),
            const SizedBox(height: 12),
            _ClaimedOffersRow(uid: _uid!),
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
          height: 148,
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

// ── Claimed Offers row ────────────────────────────────────────────────────────

class _ClaimedOffersRow extends StatelessWidget {
  final String uid;
  const _ClaimedOffersRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('offerClaims')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final hasClaims = (snap.data?.docs.length ?? 0) > 0;

        return GestureDetector(
          onTap: () => _showClaimedOffersSheet(context),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: hasClaims
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.07)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasClaims
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
                    color: hasClaims
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasClaims
                        ? Icons.local_offer_rounded
                        : Icons.local_offer_outlined,
                    color: hasClaims
                        ? const Color(0xFFF59E0B)
                        : Colors.white38,
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
                        hasClaims
                            ? 'Tap to view your claimed codes'
                            : 'Complete challenges to unlock brand offers',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
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
      },
    );
  }

  void _showClaimedOffersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ClaimedOffersSheet(uid: uid),
    );
  }
}

class _ClaimedOffersSheet extends StatelessWidget {
  final String uid;
  const _ClaimedOffersSheet({required this.uid});

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
            child: Text('My Claimed Offers',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('offerClaims')
                  .orderBy('claimedAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF7B2CBF)));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_offer_outlined,
                            color: Colors.white24, size: 44),
                        SizedBox(height: 10),
                        Text('No offers claimed yet',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Complete challenges to unlock brand codes',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 12)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final code = d['code'] as String? ?? '—';
                    final title = d['offerTitle'] as String? ?? 'Offer';
                    final brand = d['brand'] as String? ?? '';
                    final type = d['type'] as String? ?? 'percent';
                    final value = (d['value'] as num?)?.toInt() ?? 0;
                    final ts = d['claimedAt'] as Timestamp?;

                    final typeDisplay = switch (type) {
                      'percent' => '$value% off',
                      'fixed'   => '₹$value off',
                      _         => 'Free gift',
                    };
                    final typeColor = switch (type) {
                      'percent' => const Color(0xFF06B6D4),
                      'fixed'   => const Color(0xFF22C55E),
                      _         => const Color(0xFFD4A8FF),
                    };

                    String dateStr = '';
                    if (ts != null) {
                      final dt = ts.toDate();
                      dateStr = '${dt.day}/${dt.month}/${dt.year}';
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    if (brand.isNotEmpty)
                                      Text(brand,
                                          style: TextStyle(
                                              color: typeColor
                                                  .withValues(alpha: 0.80),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: typeColor
                                          .withValues(alpha: 0.35)),
                                ),
                                child: Text(typeDisplay,
                                    style: TextStyle(
                                        color: typeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: code));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('Code "$code" copied!'),
                                backgroundColor: const Color(0xFF1A0A2E),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF22C55E)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                      Icons.confirmation_number_rounded,
                                      color: Color(0xFF22C55E),
                                      size: 14),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(code,
                                        style: const TextStyle(
                                            color: Color(0xFF22C55E),
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
                          if (dateStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Claimed $dateStr',
                                  style: const TextStyle(
                                      color: Colors.white24, fontSize: 10)),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
