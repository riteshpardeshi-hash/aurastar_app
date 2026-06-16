import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/aura_tier.dart';
import '../../challenges/widgets/achievement_card.dart';
import 'user_video_detail_screen.dart';
import 'settings_screen.dart';
import 'saved_challenges_screen.dart';

// ── Achievement Cards Section ──────────────────────────────────────────────────

class _AchievementCardsSection extends StatelessWidget {
  final String uid;
  const _AchievementCardsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('achievement_cards')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final cards = snap.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Achievement Cards',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a card to share it',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final data = cards[i].data() as Map<String, dynamic>;
                  return _AchievementCardTile(cardData: data);
                },
              ),
            ),
          ],
        );
      },
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
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }

      final challengeId = widget.cardData['challengeId'] as String? ?? '';
      final challengeTitle = widget.cardData['challengeTitle'] as String? ?? '';
      final auraPoints = (widget.cardData['auraPoints'] as num?)?.toInt() ?? 0;
      final link = '$kChallengeBaseUrl/$challengeId';
      final message =
          'I completed "$challengeTitle" on Aura and earned $auraPoints Aura Points! 🏆\n\n'
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
      // share cancelled or failed — ignore
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challengeTitle = widget.cardData['challengeTitle'] as String? ?? '';
    final challengeId = widget.cardData['challengeId'] as String? ?? '';
    final auraPoints = (widget.cardData['auraPoints'] as num?)?.toInt() ?? 0;
    final username = widget.cardData['username'] as String? ?? '';
    final city = widget.cardData['city'] as String?;
    final cityRank = (widget.cardData['cityRank'] as num?)?.toInt();

    return GestureDetector(
      onTap: _shareCard,
      child: Stack(
        children: [
          // FittedBox scales the full-size card to fit the tile area.
          // RepaintBoundary wraps the full-size card so the captured
          // screenshot is at full resolution (288×~380 logical px at 3x).
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
                  child: CircularProgressIndicator(color: Color(0xFF7B2CBF), strokeWidth: 2),
                ),
              ),
            ),
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share_rounded, color: Colors.white, size: 11),
                  SizedBox(width: 4),
                  Text('Share', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
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

class MyAccountScreen extends StatelessWidget {
  const MyAccountScreen({super.key});

  static const int _xpPerLevel = 1300;
  static const _accent = Color(0xFF7B2CBF);

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;
  int _xpInLevel(int pts) => pts % _xpPerLevel;
  double _progress(int pts) => (pts % _xpPerLevel) / _xpPerLevel;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildLevelStar(int level) {
    final tier = auraTierForLevel(level);
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  tier.color.withValues(alpha: 0.35),
                  tier.color.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: tier.color.withValues(alpha: 0.70), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: tier.color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Level', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Text(
                '$level',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              Text(
                tier.name,
                style: TextStyle(
                  color: tier.color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuraPointsCard(int points) {
    final level = _level(points);
    final progress = _progress(points);
    final xpToNext = _xpPerLevel - _xpInLevel(points);

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
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
                            'Your Aura Points',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _fmt(points),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildLevelStar(level),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$xpToNext XP to Next Level',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
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
                            child: Image.asset('assets/images/bar.png', fit: BoxFit.fill),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _makeCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Widget _buildReferralCard(
      BuildContext context, String referralCode, Map<String, dynamic> userData) {
    // Existing users created before referral system — generate a code lazily
    if (referralCode.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final newCode = _makeCode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'referralCode': newCode,
            'referredBy': '',
            'referralBonusApplied': false,
            'referralCount': 0,
            'referralCompletedCount': 0,
          });
        });
      }
      return const SizedBox.shrink(); // StreamBuilder will re-render once Firestore updates
    }
    final referralCount = (userData['referralCount'] as num?)?.toInt() ?? 0;
    final completedCount =
        (userData['referralCompletedCount'] as num?)?.toInt() ?? 0;
    final link = 'https://aura-app-efae1.web.app/ref/$referralCode';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_add_rounded,
                    color: _accent, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Refer to Friends',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Share your code. When your friend completes a challenge, you earn 50 Auras!',
            style:
                TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          // Code display row
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your referral code',
                          style:
                              TextStyle(color: Colors.black38, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        referralCode,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: referralCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Referral code copied!'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, color: _accent, size: 14),
                        SizedBox(width: 4),
                        Text('Copy',
                            style: TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Stats
          Row(
            children: [
              _referralStat('$referralCount', 'Joined'),
              const SizedBox(width: 20),
              _referralStat('$completedCount', 'Completed'),
              const SizedBox(width: 20),
              _referralStat('${completedCount * 50}', 'Auras Earned'),
            ],
          ),
          const SizedBox(height: 14),
          // Share button
          GestureDetector(
            onTap: () => Share.share(
              '🎯 Join Aura Arena — copy viral challenges and earn real rewards!\n\n'
              'Use my referral code: $referralCode\n\n'
              '👉 $link\n\n'
              'Complete any challenge after signing up and I earn 50 bonus Auras! 🏆',
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
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
                      'Share Referral Link',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SpaceGrotesk',
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

  Widget _referralStat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _accent)),
          Text(label,
              style:
                  const TextStyle(color: Colors.black38, fontSize: 11)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F7FB),
        body: Center(child: Text('Not signed in.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("My Account"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("User data error: ${userSnapshot.error}"),
              ),
            );
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text("User profile not found."));
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = userData['name'] ?? 'User';
          final username = userData['username'] ?? '';
          final gender = (userData['gender'] as String? ?? '').trim();
          final totalRewards = userData['totalRewards'] ?? 0;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('submissions')
                .where('userId', isEqualTo: user.uid)
                .where('isDeleted', isEqualTo: false)
                .snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Submission error: ${submissionSnapshot.error}",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (submissionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!submissionSnapshot.hasData) {
                return const Center(child: Text("No submission data found."));
              }

              final submissions = submissionSnapshot.data!.docs.toList();

              submissions.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aCreatedAt = aData['createdAt'];
                final bCreatedAt = bData['createdAt'];
                if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
                  return bCreatedAt.compareTo(aCreatedAt);
                }
                return 0;
              });

              final totalSubmissions = submissions.length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3A1C71), Color(0xFFD76D77)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "@$username",
                            style: const TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                          if (gender.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, color: Colors.white54, size: 15),
                                const SizedBox(width: 5),
                                Text(
                                  gender,
                                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildAuraPointsCard(totalRewards),
                    _RewardsSection(level: _level(totalRewards)),
                    _buildReferralCard(
                        context,
                        userData['referralCode'] as String? ?? '',
                        userData),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.video_collection, size: 32, color: Colors.deepPurple),
                          const SizedBox(height: 10),
                          Text(
                            "$totalSubmissions",
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text("Total Videos Submitted", style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _AchievementCardsSection(uid: user.uid),
                    const SizedBox(height: 16),
                    _SavedChallengesRow(uid: user.uid),
                    const SizedBox(height: 12),
                    _ClaimedOffersRow(uid: user.uid),
                    const SizedBox(height: 24),
                    const Text(
                      "My Videos",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (submissions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "You have not submitted any videos yet.",
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Column(
                        children: submissions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final doc = entry.value;
                          final data = doc.data() as Map<String, dynamic>;

                          final auraPoints = data['auraPoints'] ?? 0;
                          final videoUrl = data['videoUrl'] ?? '';
                          final status = data['status'] ?? 'pending';
                          final aiScore = data['aiScore'];
                          final aiReason = data['aiReason'] ?? '';
                          final reviewedByAI = data['reviewedByAI'] == true;
                          final challengeTitle = data['challengeTitle'] ?? '';

                          Color statusColor;
                          String statusLabel;
                          IconData statusIcon;
                          if (status == 'approved') {
                            statusColor = Colors.green;
                            statusLabel = 'Approved';
                            statusIcon = Icons.check_circle;
                          } else if (status == 'rejected') {
                            statusColor = Colors.red;
                            statusLabel = 'Rejected';
                            statusIcon = Icons.cancel;
                          } else if (status == 'ai_error') {
                            statusColor = Colors.orange;
                            statusLabel = 'Manual Review';
                            statusIcon = Icons.pending;
                          } else {
                            statusColor = const Color(0xFF7B2CBF);
                            statusLabel = 'AI Reviewing...';
                            statusIcon = Icons.auto_awesome;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      challengeTitle.isNotEmpty ? challengeTitle : "Video ${index + 1}",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          status == 'pending'
                                              ? SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: statusColor,
                                                  ),
                                                )
                                              : Icon(statusIcon, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            statusLabel,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (reviewedByAI && aiScore != null) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, size: 16, color: Color(0xFF7B2CBF)),
                                      const SizedBox(width: 4),
                                      Text(
                                        "AI Score: $aiScore / 100",
                                        style: const TextStyle(
                                          color: Color(0xFF7B2CBF),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (status == 'approved') ...[
                                        const SizedBox(width: 12),
                                        Text(
                                          "+$auraPoints pts",
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (aiReason.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      aiReason,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ] else if (status == 'approved') ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    "Aura Points: $auraPoints",
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                if (videoUrl.toString().isNotEmpty)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UserVideoDetailScreen(
                                              videoNumber: index + 1,
                                              auraPoints: auraPoints,
                                              videoUrl: videoUrl,
                                              status: status,
                                              aiScore: aiScore,
                                              aiReason: aiReason,
                                              reviewedByAI: reviewedByAI,
                                              submissionId: doc.id,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text("View Video"),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Rewards Section ────────────────────────────────────────────────────────────

class _RewardsSection extends StatelessWidget {
  final int level;
  const _RewardsSection({required this.level});

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final unlockedCount = auraTiers
        .where((t) => level >= t.minLevel)
        .expand((t) => t.rewards)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'My Rewards',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (unlockedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unlockedCount unlocked',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Earn more Aura to unlock higher tier rewards',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        const SizedBox(height: 14),
        ...auraTiers.map((tier) => _TierRewardCard(tier: tier, level: level)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _TierRewardCard extends StatefulWidget {
  final AuraTier tier;
  final int level;
  const _TierRewardCard({required this.tier, required this.level});

  @override
  State<_TierRewardCard> createState() => _TierRewardCardState();
}

class _TierRewardCardState extends State<_TierRewardCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand unlocked tiers
    _expanded = widget.level >= widget.tier.minLevel;
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = widget.level >= widget.tier.minLevel;
    final tier = widget.tier;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnlocked
              ? tier.color.withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Tier header ──────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isUnlocked
                          ? tier.color.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.05),
                      border: Border.all(
                        color: isUnlocked
                            ? tier.color.withValues(alpha: 0.45)
                            : Colors.black12,
                      ),
                    ),
                    child: Icon(
                      isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline,
                      color: isUnlocked ? tier.color : Colors.black26,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tier.name,
                              style: TextStyle(
                                color: isUnlocked ? tier.color : Colors.black38,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? tier.color.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isUnlocked ? 'Unlocked' : 'Lv ${tier.minLevel}',
                                style: TextStyle(
                                  color: isUnlocked ? tier.color : Colors.black38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tier.rewards.length} reward${tier.rewards.length != 1 ? 's' : ''} • ${tier.unlock}',
                          style: TextStyle(
                            color: isUnlocked ? Colors.black54 : Colors.black26,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.black26,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          // ── Reward items ─────────────────────────────────────────────
          if (_expanded && tier.rewards.isNotEmpty) ...[
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                children: tier.rewards
                    .map((r) => _RewardRow(
                          reward: r,
                          isUnlocked: isUnlocked,
                          tierColor: tier.color,
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final LevelReward reward;
  final bool isUnlocked;
  final Color tierColor;
  const _RewardRow(
      {required this.reward,
      required this.isUnlocked,
      required this.tierColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? tierColor.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              reward.icon,
              color: isUnlocked ? tierColor : Colors.black26,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reward.brand} — ${reward.title}',
                  style: TextStyle(
                    color: isUnlocked ? Colors.black87 : Colors.black26,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  reward.description,
                  style: TextStyle(
                    color: isUnlocked ? Colors.black45 : Colors.black.withValues(alpha: 0.18),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isUnlocked
                ? () {
                    Clipboard.setData(ClipboardData(text: reward.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Code "${reward.code}" copied!'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? tierColor.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isUnlocked
                      ? tierColor.withValues(alpha: 0.35)
                      : Colors.black12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUnlocked ? reward.code : '??????',
                    style: TextStyle(
                      color: isUnlocked ? tierColor : Colors.black26,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (isUnlocked) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, color: tierColor, size: 11),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Saved Challenges row ───────────────────────────────────────────────────────

class _SavedChallengesRow extends StatelessWidget {
  final String uid;
  const _SavedChallengesRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('saved_challenges')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final hasSaved = (snap.data?.docs.length ?? 0) > 0;

        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SavedChallengesScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF12102A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasSaved
                    ? const Color(0xFF7B2CBF).withValues(alpha: 0.40)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2CBF).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    color: hasSaved ? const Color(0xFFD4A8FF) : Colors.white38,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saved Challenges',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        hasSaved
                            ? 'Tap to see your saved list'
                            : 'Bookmark challenges to try later',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
              ],
            ),
          ),
        );
      },
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
          .collection('users').doc(uid)
          .collection('offerClaims')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final hasClaims = (snap.data?.docs.length ?? 0) > 0;

        return GestureDetector(
          onTap: () => _showClaimedOffersSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  width: 36, height: 36,
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
            width: 36, height: 4,
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
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(uid)
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.local_offer_outlined,
                            color: Colors.white24, size: 44),
                        SizedBox(height: 10),
                        Text('No offers claimed yet',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 14)),
                        SizedBox(height: 4),
                        Text(
                            'Complete challenges to unlock brand codes',
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
                    final d     = docs[i].data() as Map<String, dynamic>;
                    final code  = d['code']       as String? ?? '—';
                    final title = d['offerTitle'] as String? ?? 'Offer';
                    final brand = d['brand']      as String? ?? '';
                    final type  = d['type']       as String? ?? 'percent';
                    final value = (d['value']     as num?)?.toInt() ?? 0;
                    final ts    = d['claimedAt']  as Timestamp?;

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
                              Clipboard.setData(
                                  ClipboardData(text: code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Code "$code" copied!'),
                                  backgroundColor:
                                      const Color(0xFF1A0A2E),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                ),
                              );
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
                                      color: Colors.white24,
                                      fontSize: 10)),
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
