import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../core/models/aura_tier.dart';
import '../../shared/widgets/video_thumbnail_widget.dart' show videoThumbnailCache;
import '../../shared/widgets/level_up_sheet.dart';
import '../../shared/widgets/wallet_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../challenges/screens/challenge_detail.dart';
import '../explore/screens/explore_creators_screen.dart';
import '../challenges/screens/category_challenges_screen.dart';
import '../challenges/screens/trending_screen.dart';
import '../explore/screens/creator_videos_screen.dart';
import '../../shared/widgets/aura_action_sheet.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../account/screens/my_account_screen.dart';
import '../creator/admin/creator_admin_screen.dart';
import '../creator/screens/creator_dashboard_screen.dart';
import '../creator/screens/brand_dashboard_screen.dart';
import '../creator/screens/create_creator_profile_screen.dart';
import '../admin/screens/admin_screen.dart';
import '../video/screens/preview_screen.dart';
import '../../core/services/upload_queue_service.dart';
import '../arcade/screens/arcade_screen.dart';
import '../arcade/services/arcade_progress_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int? _lastKnownLevel;
  bool _atRiskAlertShown = false;
  int _arcadeKey = 0;

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);
  static const int _xpPerLevel = 1300;

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildScaffold(context,
          points: 0,
          isAdmin: false,
          isBrand: false,
          isCreator: false,
          userId: '',
          displayName: 'Guest',
          streakDay: 0,
          lastStreakDate: '');
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: Text('Failed to load profile.',
                  style: TextStyle(color: Colors.white54)),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final userData = snap.data!.data() as Map<String, dynamic>? ?? {};
        final isAdmin = userData['isAdmin'] as bool? ?? false;
        final isBrand = userData['isBrand'] as bool? ?? false;
        final isCreator = userData['isCreator'] as bool? ?? false;
        final points = (userData['totalRewards'] ?? 0) as int;
        final level = _level(points);
        final displayName =
            (userData['name'] as String?)?.trim().isNotEmpty == true
                ? userData['name'] as String
                : userData['username'] as String? ?? 'User';
        final streakDay = (userData['streakDay'] as num?)?.toInt() ?? 0;
        final lastStreakDate = userData['lastStreakDate'] as String? ?? '';

        if (_lastKnownLevel != null && level > _lastKnownLevel!) {
          final oldTier = auraTierForLevel(_lastKnownLevel!);
          final newTier = auraTierForLevel(level);
          if (newTier.minLevel > oldTier.minLevel) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showLevelUpModal(context, level, newTier);
            });
          }
        }
        _lastKnownLevel = level;

        // At-risk streak alert: show once per session after 7 pm
        if (!_atRiskAlertShown && streakDay > 0 && DateTime.now().hour >= 19) {
          final now = DateTime.now();
          final todayStr =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          if (lastStreakDate != todayStr) {
            _atRiskAlertShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Text('⚠️', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your streak ends at midnight — play now to save it!',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF2D1800),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 5),
                    action: SnackBarAction(
                      label: 'Play',
                      textColor: Colors.amber,
                      onPressed: () {},
                    ),
                  ),
                );
            });
          }
        }

        return _buildScaffold(
          context,
          points: points,
          isAdmin: isAdmin,
          isBrand: isBrand,
          isCreator: isCreator,
          userId: user.uid,
          displayName: displayName,
          streakDay: streakDay,
          lastStreakDate: lastStreakDate,
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required int points,
    required bool isAdmin,
    required bool isBrand,
    required bool isCreator,
    required String userId,
    required String displayName,
    required int streakDay,
    required String lastStreakDate,
  }) {
    final tier = auraTierForLevel(_level(points));

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _buildHeader(
                        context, points, tier, displayName, userId),
                  ),
                ),
                SliverToBoxAdapter(
                    child: _buildStreakBanner(streakDay, lastStreakDate)),
                SliverToBoxAdapter(
                    child: _ArcadeTeaserBanner(
                      key: ValueKey(_arcadeKey),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ArcadeScreen()),
                      ).then((_) {
                        if (mounted) setState(() => _arcadeKey++);
                      }),
                    )),
                const SliverToBoxAdapter(child: _PendingUploadBanner()),
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(
                    child: _buildAuraArenaNewSection(context)),
                SliverToBoxAdapter(child: _buildBrandAuraSection(context)),
                SliverToBoxAdapter(child: _buildCreatorVideosSection(context)),
                SliverToBoxAdapter(child: _buildCategorySection(context)),
                SliverToBoxAdapter(child: _buildTrendingSection(context)),
                if (!isCreator && !isBrand && !isAdmin)
                  SliverToBoxAdapter(
                      child:
                          _buildBecomeCreatorBanner(context, userId, points)),
                if (isCreator)
                  SliverToBoxAdapter(
                      child: _buildCreatorTools(context, userId)),
                if (isBrand || isAdmin)
                  SliverToBoxAdapter(
                      child: _buildBrandTools(context, userId, isBrand, points)),
                if (isAdmin)
                  SliverToBoxAdapter(child: _buildAdminButton(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, int points, AuraTier tier,
      String displayName, String userId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Logo text ─────────────────────────────────
          SizedBox(
            height: 20,
            width: 110,
            child: Image.asset(
              'assets/images/Aura arena.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),

          const Spacer(),

          // ── Name + Points ─────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WalletScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0A2E),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: _accent.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/homescreen/separate elements/coin icon.png',
                        height: 13,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$points',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // ── Avatar ────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyAccountScreen())),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4B6EF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _accent, width: 1.5),
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Streak Banner ──────────────────────────────────────────────────────────
  Widget _buildStreakBanner(int streakDay, String lastStreakDate) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    final qualifiedToday    = lastStreakDate == todayStr;
    final qualifiedYesterday = lastStreakDate == yesterdayStr;
    final bonusJustCredited = streakDay == 0 && qualifiedToday;

    // Broken: had an active streak but missed at least one full day
    final broken = streakDay > 0 &&
        !qualifiedToday &&
        !qualifiedYesterday &&
        lastStreakDate.isNotEmpty;

    // At risk: after 7 pm, streak active, haven't played today yet
    final atRisk = !broken && streakDay > 0 && !qualifiedToday && now.hour >= 19;

    if (streakDay == 0 && !bonusJustCredited) return const SizedBox.shrink();

    final displayDay = bonusJustCredited ? 7 : streakDay;
    const streakColor = Color(0xFFFF6B35);

    // State-driven appearance
    late Color borderColor;
    late Color labelColor;
    late String emoji;
    late String label;

    if (broken) {
      borderColor = const Color(0xFFFF4444).withValues(alpha: 0.45);
      labelColor  = const Color(0xFFFF6B6B);
      emoji       = '💔';
      label       = 'Streak broken — play today to start a new one!';
    } else if (bonusJustCredited) {
      borderColor = streakColor.withValues(alpha: 0.50);
      labelColor  = streakColor;
      emoji       = '🎉';
      label       = '7-Day Streak complete! +50 Auras awarded';
    } else if (atRisk) {
      borderColor = Colors.amber.withValues(alpha: 0.65);
      labelColor  = Colors.amber;
      emoji       = '⚠️';
      label       = 'Streak ends at midnight — play now to save it!';
    } else if (qualifiedToday) {
      borderColor = streakColor.withValues(alpha: 0.40);
      labelColor  = streakColor;
      emoji       = '🔥';
      label       = 'Day $displayDay/7 — keep it up!';
    } else {
      borderColor = streakColor.withValues(alpha: 0.20);
      labelColor  = Colors.white54;
      emoji       = '🔥';
      label       = 'Day $displayDay/7 — play a challenge to continue';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Day dot tracker ──────────────────────────────────────
                Row(
                  children: List.generate(7, (i) {
                    final dayNum = i + 1;
                    final isCompleted = broken
                        ? false
                        : (dayNum < displayDay ||
                            (dayNum == displayDay && (qualifiedToday || bonusJustCredited)));
                    final isCurrent =
                        !broken && !bonusJustCredited && dayNum == displayDay && !qualifiedToday;
                    final isPast = broken && dayNum <= displayDay;

                    Color dotBg;
                    Border? dotBorder;
                    Widget dotChild;

                    if (isPast) {
                      dotBg = const Color(0xFFFF4444).withValues(alpha: 0.18);
                      dotChild = const Icon(Icons.close_rounded,
                          color: Color(0xFFFF6B6B), size: 11);
                    } else if (isCompleted) {
                      dotBg = streakColor;
                      dotChild = const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 12);
                    } else if (isCurrent) {
                      dotBg     = Colors.transparent;
                      dotBorder = Border.all(
                          color: atRisk ? Colors.amber : streakColor, width: 1.5);
                      dotChild  = Text(
                        '$dayNum',
                        style: TextStyle(
                          color: atRisk ? Colors.amber : streakColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    } else {
                      dotBg    = Colors.white.withValues(alpha: 0.06);
                      dotChild = Text(
                        '$dayNum',
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                      );
                    }

                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                        height: 28,
                        decoration: BoxDecoration(
                          color: dotBg,
                          shape: BoxShape.circle,
                          border: dotBorder,
                        ),
                        child: Center(child: dotChild),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────────────────
  Widget _buildHeroSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('creatorId', isEqualTo: 'system')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        String title = 'Bollywood Walk';
        int auraPoints = 150;
        String videoUrl = '';
        String instructions = '';
        String challengeId = '';

        if (docs.isNotEmpty) {
          final data = docs.first.data() as Map<String, dynamic>;
          title = data['title'] as String? ?? title;
          auraPoints = (data['auraPoints'] as num?)?.toInt() ?? auraPoints;
          videoUrl = data['videoUrl'] as String? ?? '';
          instructions = data['instructions'] as String? ?? '';
          challengeId = docs.first.id;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: Container(
            height: 320,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4B3EAA), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Auto-generated video thumbnail
                  _VideoThumbnailWidget(
                    videoUrl: videoUrl,
                    fallbackAsset: 'assets/images/homescreen/hero banner.png',
                  ),
                  // Bottom-to-top dark gradient for text readability
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.2, 1.0],
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                  // Content — bottom-left
                  Positioned(
                    left: 16,
                    bottom: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Aura points row
                        Row(
                          children: [
                            Image.asset(
                              'assets/images/homescreen/separate elements/coin icon.png',
                              height: 24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$auraPoints',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'ClashDisplay',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Challenge title
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay',
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Take this Challenge button
                        GestureDetector(
                          onTap: challengeId.isNotEmpty
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChallengeDetail(
                                        title: title,
                                        instructions: instructions,
                                        videoUrl: videoUrl,
                                        challengeId: challengeId,
                                      ),
                                    ),
                                  )
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6B2FD9), Color(0xFF9B4DFF)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'Take this Challenge',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Diamond pagination indicators
                        Row(
                          children: const [
                            Icon(Icons.diamond_outlined,
                                color: Colors.white54, size: 14),
                            SizedBox(width: 6),
                            Icon(Icons.diamond_outlined,
                                color: Colors.white54, size: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Aura Arena New ─────────────────────────────────────────────────────────
  Widget _buildAuraArenaNewSection(BuildContext context) {
    const staticImages = [
      'assets/images/homescreen/challenge 1.png',
      'assets/images/homescreen/challenge 2.png',
      'assets/images/homescreen/challenge 3.png',
    ];
    const fallbackTitles = ['Book on Head', 'Perfect Circle', 'Sunglass Challenge'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aura Arena New',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay',
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AllGeneralChallengesScreen()),
                ),
                child: const Text(
                  '>>>',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13, letterSpacing: 2),
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .where('creatorId', isEqualTo: 'system')
              .limit(3)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(3, (i) {
                  final hasDoc = i < docs.length;
                  final doc = hasDoc ? docs[i] : null;
                  final data =
                      doc != null ? doc.data() as Map<String, dynamic> : null;
                  final title =
                      data?['title'] as String? ?? fallbackTitles[i];
                  final videoUrl = data?['videoUrl'] as String? ?? '';
                  final instructions =
                      data?['instructions'] as String? ?? '';
                  final challengeId = doc?.id ?? '';

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: GestureDetector(
                        onTap: challengeId.isNotEmpty
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChallengeDetail(
                                      title: title,
                                      instructions: instructions,
                                      videoUrl: videoUrl,
                                      challengeId: challengeId,
                                    ),
                                  ),
                                )
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 122,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _VideoThumbnailWidget(
                                  videoUrl: videoUrl,
                                  fallbackAsset: staticImages[i],
                                ),
                                // Bottom gradient + label
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        6, 18, 6, 7),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black87,
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'SpaceGrotesk',
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _buildPromoBanner(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 120,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-width background image, anchored to show figures on the right
              Image.asset(
                'assets/images/homescreen/separate elements/leaderboard.png',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
              // Left-to-right dark gradient so text is readable
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.5, 0.75],
                    colors: [
                      Colors.black,
                      Color(0xDD000000),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Text left side
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 175, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Lorem\nipsum dolor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        fontFamily: 'ClashDisplay',
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Lorem ipsum dolor sit amet,\nLorem ipsum dolor sit amet,',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        height: 1.5,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Brand Aura ─────────────────────────────────────────────────────────────
  Widget _buildBrandAuraSection(BuildContext context) {
    const gridImages = [
      'assets/images/homescreen/brand challenge 1.png',
      'assets/images/homescreen/brand challenge 2.png',
      'assets/images/homescreen/brand challenge 3.png',
    ];
    const gridFallbackTitles = [
      'Plank Challenge',
      'Bollywood Walk',
      'Zero Mess Challenge'
    ];
    const featureImages = [
      'assets/images/homescreen/brand challenge 4.png',
      'assets/images/homescreen/brand challenge 5.png',
    ];
    const featureFallbackTitles = ['FLIP THE CAN', 'FASHION WALK'];
    const featureFallbackDesc = [
      'Land the perfect can flip\nand earn Aura.',
      'Own the walk.\nEarn Aura with every pose.',
    ];
    const featureFallbackPoints = [150, 250];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Brand Aura',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay',
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExploreCreatorsScreen()),
                ),
                child: const Text(
                  '>>>',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13, letterSpacing: 2),
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .limit(5)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];

            return Column(
              children: [
                // 3-column grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: List.generate(3, (i) {
                      final hasDoc = i < docs.length;
                      final doc = hasDoc ? docs[i] : null;
                      final data = doc != null
                          ? doc.data() as Map<String, dynamic>
                          : null;
                      final title = data?['title'] as String? ??
                          gridFallbackTitles[i];
                      final videoUrl = data?['videoUrl'] as String? ?? '';
                      final instructions =
                          data?['instructions'] as String? ?? '';
                      final challengeId = doc?.id ?? '';

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: GestureDetector(
                            onTap: challengeId.isNotEmpty
                                ? () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChallengeDetail(
                                          title: title,
                                          instructions: instructions,
                                          videoUrl: videoUrl,
                                          challengeId: challengeId,
                                        ),
                                      ),
                                    )
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 122,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _VideoThumbnailWidget(
                                      videoUrl: videoUrl,
                                      fallbackAsset: gridImages[i],
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            6, 18, 6, 7),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black87,
                                            ],
                                          ),
                                        ),
                                        child: Text(
                                          title,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'SpaceGrotesk',
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // 2 feature cards
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: List.generate(2, (i) {
                      final docIndex = 3 + i;
                      final hasDoc = docIndex < docs.length;
                      final doc = hasDoc ? docs[docIndex] : null;
                      final data = doc != null
                          ? doc.data() as Map<String, dynamic>
                          : null;
                      final title = data?['title'] as String? ??
                          featureFallbackTitles[i];
                      final description =
                          data?['instructions'] as String? ??
                              featureFallbackDesc[i];
                      final auraPoints =
                          (data?['auraPoints'] as num?)?.toInt() ??
                              featureFallbackPoints[i];
                      final videoUrl = data?['videoUrl'] as String? ?? '';
                      final challengeId = doc?.id ?? '';

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                          child: GestureDetector(
                            onTap: challengeId.isNotEmpty
                                ? () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChallengeDetail(
                                          title: title,
                                          instructions: description,
                                          videoUrl: videoUrl,
                                          challengeId: challengeId,
                                        ),
                                      ),
                                    )
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 132,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _VideoThumbnailWidget(
                                      videoUrl: videoUrl,
                                      fallbackAsset: featureImages[i],
                                    ),
                                    Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.45)),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            title.toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.3,
                                              fontFamily: 'ClashDisplay',
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white60,
                                              fontSize: 9,
                                              height: 1.35,
                                              fontFamily: 'SpaceGrotesk',
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Image.asset(
                                                'assets/images/homescreen/separate elements/coin icon.png',
                                                height: 14,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '$auraPoints',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'SpaceGrotesk',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Trending ───────────────────────────────────────────────────────────────
  Widget _buildTrendingSection(BuildContext context) {
    const trendingImages = [
      'assets/images/homescreen/challenge 1.png',
      'assets/images/homescreen/brand challenge 2.png',
      'assets/images/homescreen/challenge 2.png',
      'assets/images/homescreen/brand challenge 3.png',
    ];
    const fallbackTitles = [
      'Yoga Pose Challenge',
      'Rock Star Challenge',
      'Street Dance Challenge',
      'Mirror Challenge',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Trending',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay',
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TrendingScreen())),
                child: const Text('See All ›',
                    style: TextStyle(color: Color(0xFF9B4DCA), fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .limit(4)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            final count = docs.isEmpty ? 2 : docs.length;

            return Column(
              children: List.generate(count, (i) {
                final hasDoc = i < docs.length;
                final doc = hasDoc ? docs[i] : null;
                final data =
                    doc != null ? doc.data() as Map<String, dynamic> : null;
                final title =
                    data?['title'] as String? ?? fallbackTitles[i % fallbackTitles.length];
                final challengeId = doc?.id ?? '';
                final videoUrl = data?['videoUrl'] as String? ?? '';
                final views = (data?['views'] as num?)?.toInt() ?? 0;
                final auraPoints =
                    (data?['auraPoints'] as num?)?.toInt() ?? 150;
                final instructions =
                    data?['instructions'] as String? ?? '';

                return _buildTrendingCard(
                  context: context,
                  imagePath: trendingImages[i % trendingImages.length],
                  title: title,
                  views: views,
                  auraPoints: auraPoints,
                  challengeId: challengeId,
                  videoUrl: videoUrl,
                  instructions: instructions,
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrendingCard({
    required BuildContext context,
    required String imagePath,
    required String title,
    required int views,
    required int auraPoints,
    required String challengeId,
    required String videoUrl,
    required String instructions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: GestureDetector(
        onTap: challengeId.isNotEmpty
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChallengeDetail(
                      title: title,
                      instructions: instructions,
                      videoUrl: videoUrl,
                      challengeId: challengeId,
                    ),
                  ),
                )
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _VideoThumbnailWidget(
                  videoUrl: videoUrl,
                  fallbackAsset: imagePath,
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.40, 1.0],
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 14,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_red_eye_outlined,
                        color: Colors.white60,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(views),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Image.asset(
                        'assets/images/homescreen/separate elements/like.png',
                        height: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$auraPoints',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (challengeId.isNotEmpty)
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChallengeDetail(
                                title: title,
                                instructions: instructions,
                                videoUrl: videoUrl,
                                challengeId: challengeId,
                              ),
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/homescreen/separate elements/button.png',
                            height: 32,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Creator Videos ────────────────────────────────────────────────────────
  Widget _buildCreatorVideosSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isCreator', isEqualTo: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Creator Videos',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'ClashDisplay')),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CreatorVideosScreen())),
                    child: const Text('See All ›',
                        style: TextStyle(color: Color(0xFF9B4DCA), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data     = docs[i].data() as Map<String, dynamic>;
                  final pageName = data['pageName'] as String? ?? data['name'] as String? ?? 'Creator';
                  final imgUrl   = data['profileImageUrl'] as String? ?? '';
                  final followers = (data['followerCount'] as num?)?.toInt() ?? 0;

                  return GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CreatorVideosScreen())),
                    child: Container(
                      width: 72,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: _accent.withValues(alpha: 0.45), width: 1.5),
                            ),
                            child: imgUrl.isNotEmpty
                                ? ClipOval(child: Image.network(imgUrl, fit: BoxFit.cover))
                                : Center(
                                    child: Text(
                                      pageName.isNotEmpty ? pageName[0].toUpperCase() : 'C',
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 5),
                          Text(pageName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600,
                                  fontFamily: 'SpaceGrotesk')),
                          if (followers > 0)
                            Text('${_fmt(followers)} followers',
                                style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'SpaceGrotesk')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Category Videos ───────────────────────────────────────────────────────
  Widget _buildCategorySection(BuildContext context) {
    const categories = [
      ('Dance',   Icons.music_note_rounded,        Color(0xFF4B6EF6)),
      ('Fitness', Icons.fitness_center_rounded,    Color(0xFF22C55E)),
      ('Fashion', Icons.checkroom_rounded,         Color(0xFFFF6B9D)),
      ('Sports',  Icons.sports_basketball_rounded, Color(0xFFF97316)),
      ('Comedy',  Icons.mood_rounded,              Color(0xFFEAB308)),
      ('Skill',   Icons.psychology_rounded,        Color(0xFF06B6D4)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Category Videos',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'ClashDisplay')),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AllGeneralChallengesScreen())),
                child: const Text('See All ›',
                    style: TextStyle(color: Color(0xFF9B4DCA), fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (_, i) {
              final (name, icon, color) = categories[i];
              return GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CategoryChallengesScreen(category: name))),
                child: Container(
                  width: 78,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.30)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 26),
                      const SizedBox(height: 6),
                      Text(name,
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'SpaceGrotesk')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Become Creator banner (regular users only) ─────────────────────────────
  Widget _buildBecomeCreatorBanner(
      BuildContext context, String userId, int points) {
    return GestureDetector(
      onTap: () {
        if (points < 500) {
          _showCreatorGateSheet(context, points);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const CreateCreatorProfileScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0A30), Color(0xFF0A1630)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: _accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded,
                  color: Color(0xFFD4A8FF), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Become a Creator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    points >= 500
                        ? 'You qualify! Launch challenges & grow your brand'
                        : '${500 - points} Aura to unlock — keep playing!',
                    style: TextStyle(
                      color: points >= 500
                          ? const Color(0xFFD4A8FF)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              points >= 500
                  ? Icons.arrow_forward_ios_rounded
                  : Icons.lock_outline_rounded,
              color: points >= 500 ? Colors.white54 : Colors.white24,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  // ── Creator Tools (content creators only) ─────────────────────────────────
  Widget _buildCreatorTools(BuildContext context, String userId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Creator Tools',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 10),
          _toolButton(
            label: 'Creator Dashboard',
            colors: const [Color(0xFF7B2FF7), Color(0xFFF107A3)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CreatorDashboardScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ── Creator gate modal ─────────────────────────────────────────────────────
  void _showCreatorGateSheet(BuildContext context, int currentPoints) {
    const required = 500;
    final progress = (currentPoints / required).clamp(0.0, 1.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3)),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: _accent.withValues(alpha: 0.40), width: 1.5),
              ),
              child:
                  const Icon(Icons.lock_outline_rounded, color: _accent, size: 30),
            ),
            const SizedBox(height: 18),
            const Text(
              '500 Aura Required',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ClashDisplay'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Earn 500 Aura points by completing challenges\nto unlock Creator status.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            // Progress bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$currentPoints Aura',
                  style: const TextStyle(
                      color: Color(0xFFD4A8FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  '${required - currentPoints.clamp(0, required)} to go',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF7B2CBF)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: const Text('Keep Playing'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Brand Tools (brands/admin only) ────────────────────────────────────────
  Widget _buildBrandTools(
      BuildContext context, String userId, bool isBrand, int points) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Brand Tools',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _toolButton(
                  label: isBrand ? 'Brand Dashboard' : 'Start Brand Page',
                  colors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  onTap: () async {
                    final doc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .get();
                    final data = doc.data() ?? {};
                    final alreadyBrand = data['isBrand'] as bool? ?? false;
                    final currentPoints =
                        (data['totalRewards'] as num?)?.toInt() ?? 0;
                    if (!context.mounted) return;
                    if (!alreadyBrand && currentPoints < 500) {
                      _showCreatorGateSheet(context, currentPoints);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => alreadyBrand
                            ? const BrandDashboardScreen()
                            : const CreateCreatorProfileScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toolButton(
                  label: 'Brand Analytics',
                  colors: const [Color(0xFF5B2EFF), Color(0xFF9B4DFF)],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreatorAdminScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFB91C1C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Admin Panel',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'SpaceGrotesk')),
        ),
      ),
    );
  }

  Widget _toolButton({
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: 'SpaceGrotesk')),
        ),
      ),
    );
  }

  // ── Level-up modal ─────────────────────────────────────────────────────────
  void _showLevelUpModal(BuildContext context, int level, AuraTier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LevelUpSheet(level: level, tier: tier),
    );
  }

  // ── Bottom Nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: SizedBox(
          height: 74,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Pill-shaped nav bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 62,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(
                        icon: Icons.home_rounded,
                        label: 'Home',
                        active: true,
                        onTap: () {},
                      ),
                      _navItem(
                        icon: Icons.sports_esports_rounded,
                        label: 'Arcade',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ArcadeScreen()),
                        ).then((_) {
                          if (mounted) setState(() => _arcadeKey++);
                        }),
                      ),
                      const SizedBox(width: 58),
                      _navItem(
                        icon: Icons.leaderboard_rounded,
                        label: 'Leaderboard',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LeaderboardScreen()),
                        ),
                      ),
                      _navItem(
                        icon: Icons.person_rounded,
                        label: 'Profile',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyAccountScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Floating centre button
              Positioned(
                top: 0,
                child: GestureDetector(
                  onTap: () => showAuraActionSheet(context),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D0020),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Image.asset(
                        'assets/images/Aura Arena Mono.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? _accent : Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _accent : Colors.white38,
                fontSize: 9,
                fontFamily: 'SpaceGrotesk',
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── Arcade Teaser Banner ──────────────────────────────────────────────────────

class _ArcadeTeaserBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _ArcadeTeaserBanner({super.key, required this.onTap});

  @override
  State<_ArcadeTeaserBanner> createState() => _ArcadeTeaserBannerState();
}

class _ArcadeTeaserBannerState extends State<_ArcadeTeaserBanner> {
  ArcadeProgress? _progress;

  @override
  void initState() {
    super.initState();
    ArcadeProgressService.load().then((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF7B2CBF);
    const cyan = Color(0xFF48D7FF);
    const textMuted = Color(0xFF9CA8C7);

    final completed = _progress?.completedToday.length ?? 0;
    final streak = _progress?.streak ?? 0;
    final allDone = completed == 3;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF120828), Color(0xFF0A1020)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: violet.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: violet.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.sports_esports_rounded,
                    color: Color(0xFFD4A8FF), size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aura Arcade',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _progress == null
                        ? 'Daily Arcade · 3 games'
                        : '$completed/3 complete today'
                            '${streak > 0 ? ' · $streak day streak' : ''}',
                    style: TextStyle(
                      color: allDone ? cyan : textMuted,
                      fontSize: 12,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: violet,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Play',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Video Thumbnail Widget ─────────────────────────────────────────────────
class _VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  final String fallbackAsset;

  const _VideoThumbnailWidget({
    required this.videoUrl,
    required this.fallbackAsset,
  });

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_VideoThumbnailWidget old) {
    super.didUpdateWidget(old);
    if (old.videoUrl != widget.videoUrl) {
      setState(() => _thumb = null);
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.videoUrl.isEmpty) return;
    // Check shared in-memory cache first
    if (videoThumbnailCache.containsKey(widget.videoUrl)) {
      if (mounted) setState(() => _thumb = videoThumbnailCache[widget.videoUrl]);
      return;
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      );
      if (bytes != null) videoThumbnailCache[widget.videoUrl] = bytes;
      if (mounted) setState(() => _thumb = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Always show fallback immediately; overlay the real thumbnail once ready
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(widget.fallbackAsset, fit: BoxFit.cover),
        if (_thumb != null)
          Image.memory(
            _thumb!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
      ],
    );
  }

}

// ── Pending upload recovery banner ────────────────────────────────────────────

class _PendingUploadBanner extends StatefulWidget {
  const _PendingUploadBanner();

  @override
  State<_PendingUploadBanner> createState() => _PendingUploadBannerState();
}

class _PendingUploadBannerState extends State<_PendingUploadBanner> {
  PendingUpload? _pending;
  bool _dismissed = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await UploadQueueService.getPending();
    if (mounted) setState(() { _pending = p; _checked = true; });
  }

  Future<void> _retry() async {
    final p = _pending;
    if (p == null) return;
    setState(() => _dismissed = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          videoPath:      p.videoPath,
          challengeId:    p.challengeId,
          challengeTitle: p.challengeTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _pending == null || _dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.upload_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload pending',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _pending!.challengeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text(
              'Retry',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: () async {
              await UploadQueueService.clear();
              setState(() => _dismissed = true);
            },
          ),
        ],
      ),
    );
  }
}
