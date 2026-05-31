import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/aura_tier.dart';
import '../../shared/widgets/level_up_sheet.dart';
import '../../shared/widgets/wallet_screen.dart';
import '../../shared/widgets/video_thumbnail_widget.dart';
import '../notifications/notifications_screen.dart';
import '../search/search_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../challenges/screens/brand_challenges_screen.dart';
import '../challenges/screens/challenge_detail.dart';
import '../explore/screens/explore_creators_screen.dart';
import '../home/screens/home_feed_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../account/screens/my_account_screen.dart';
import '../creator/admin/creator_admin_screen.dart';
import '../creator/screens/creator_home_screen.dart';
import '../creator/screens/create_creator_profile_screen.dart';
import '../admin/screens/admin_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int? _lastKnownLevel;

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);
  static const int _xpPerLevel = 1300;

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildScaffold(
        context,
        points: 0,
        isAdmin: false,
        isBrand: false,
        userId: '',
        displayName: 'Guest',
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final userData = snap.data!.data() as Map<String, dynamic>? ?? {};
        final isAdmin = userData['isAdmin'] as bool? ?? false;
        final isBrand = userData['isCreator'] as bool? ?? false;
        final points = (userData['totalRewards'] ?? 0) as int;
        final level = _level(points);
        final displayName =
            (userData['name'] as String?)?.trim().isNotEmpty == true
                ? userData['name'] as String
                : userData['username'] as String? ?? 'User';

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

        return _buildScaffold(
          context,
          points: points,
          isAdmin: isAdmin,
          isBrand: isBrand,
          userId: user.uid,
          displayName: displayName,
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required int points,
    required bool isAdmin,
    required bool isBrand,
    required String userId,
    required String displayName,
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
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(
                    child: _buildAuraArenaNewSection(context)),
                SliverToBoxAdapter(child: _buildBrandAuraSection(context)),
                SliverToBoxAdapter(child: _buildTrendingSection(context)),
                if (isBrand || isAdmin)
                  SliverToBoxAdapter(
                      child: _buildBrandTools(context, userId, isBrand)),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        children: [
          // ── Row 1: Logo | Search | Notif | Avatar ──────────────────────
          Row(
            children: [
              Image.asset(
                'assets/images/Aura arena.png',
                width: 140,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SearchScreen())),
                child: const Icon(Icons.search_rounded,
                    color: Colors.white70, size: 24),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen())),
                child: const Icon(Icons.notifications_none_rounded,
                    color: Colors.white70, size: 24),
              ),
              const SizedBox(width: 14),
              // Avatar
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MyAccountScreen())),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4B6EF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white30, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Row 2: Display name | Points pill ──────────────────────────
          Row(
            children: [
              Text(
                displayName,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WalletScreen())),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0A2E),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: _accent.withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.diamond, color: _accent, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '$points',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
        if (docs.isEmpty) return const SizedBox.shrink();

        final doc = docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final title = data['title'] as String? ?? 'Challenge';
        final videoUrl = data['videoUrl'] as String? ?? '';
        final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;
        final instructions = data['instructions'] as String? ?? '';

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChallengeDetail(
                  title: title,
                  instructions: instructions,
                  videoUrl: videoUrl,
                  challengeId: doc.id,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Thumbnail
                    VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                    // Gradient overlay
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.25, 1.0],
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                    // Content
                    Positioned(
                      left: 16,
                      bottom: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.diamond,
                                  color: _accent, size: 18),
                              const SizedBox(width: 5),
                              Text(
                                '$auraPoints',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 9),
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Text(
                              'Take this Challenge',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Dot indicators
                          Row(
                            children: [
                              const Icon(Icons.diamond_outlined,
                                  color: Colors.white70, size: 10),
                              const SizedBox(width: 6),
                              const Icon(Icons.diamond_outlined,
                                  color: Colors.white30, size: 10),
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
        );
      },
    );
  }

  // ── Aura Arena New ─────────────────────────────────────────────────────────
  Widget _buildAuraArenaNewSection(BuildContext context) {
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
                    fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AllGeneralChallengesScreen()),
                ),
                child: const Text('>>>',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        letterSpacing: 2)),
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
            if (docs.isEmpty) {
              return const SizedBox(
                height: 110,
                child: Center(
                  child: Text('No challenges yet',
                      style: TextStyle(color: Colors.white38)),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(docs.length, (i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] as String? ?? '';
                  final videoUrl = data['videoUrl'] as String? ?? '';
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: _thumbnailCard(
                        context: context,
                        videoUrl: videoUrl,
                        title: title,
                        height: 110,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChallengeDetail(
                              title: title,
                              instructions:
                                  data['instructions'] as String? ?? '',
                              videoUrl: videoUrl,
                              challengeId: doc.id,
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
        child: Container(
          height: 110,
          color: const Color(0xFF0D0020),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -10,
                top: 0,
                bottom: 0,
                width: 200,
                child: Opacity(
                  opacity: 0.18,
                  child: Image.asset(
                    'assets/images/Aura arena.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Copy. Score.',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.1),
                    ),
                    const Text(
                      'Earn Aura.',
                      style: TextStyle(
                          color: _accent,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Complete challenges and climb\nto the top of the leaderboard.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 11, height: 1.45),
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
                    fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExploreCreatorsScreen()),
                ),
                child: const Text('>>>',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        letterSpacing: 2)),
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

            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Center(
                    child: Text(
                      'No brand challenges yet',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                ),
              );
            }

            final gridDocs = docs.take(3).toList();
            final featureDocs = docs.skip(3).take(2).toList();

            return Column(
              children: [
                // 3-column thumbnail grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: List.generate(gridDocs.length, (i) {
                      final doc = gridDocs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final title = data['title'] as String? ?? '';
                      final videoUrl = data['videoUrl'] as String? ?? '';
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: _thumbnailCard(
                            context: context,
                            videoUrl: videoUrl,
                            title: title,
                            height: 110,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChallengeDetail(
                                  title: title,
                                  instructions:
                                      data['instructions'] as String? ?? '',
                                  videoUrl: videoUrl,
                                  challengeId: doc.id,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Feature cards (up to 2)
                if (featureDocs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: List.generate(featureDocs.length, (i) {
                        final doc = featureDocs[i];
                        final data = doc.data() as Map<String, dynamic>;
                        final title = data['title'] as String? ?? '';
                        final videoUrl = data['videoUrl'] as String? ?? '';
                        final auraPoints =
                            (data['auraPoints'] as num?)?.toInt() ?? 150;
                        final instructions =
                            data['instructions'] as String? ?? '';
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChallengeDetail(
                                    title: title,
                                    instructions: instructions,
                                    videoUrl: videoUrl,
                                    challengeId: doc.id,
                                  ),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  height: 120,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      VideoThumbnailWidget(
                                          videoUrl: videoUrl,
                                          fit: BoxFit.cover),
                                      Container(color: Colors.black54),
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
                                                  letterSpacing: 0.3),
                                            ),
                                            if (instructions.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                instructions,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 10,
                                                    height: 1.3),
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(Icons.diamond,
                                                    color: _accent, size: 12),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '$auraPoints',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Trending',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .limit(5)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Center(
                    child: Text('No trending content yet',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] as String? ?? 'Challenge';
                final challengeId = doc.id;
                final videoUrl = data['videoUrl'] as String? ?? '';
                final views = (data['views'] as num?)?.toInt() ?? 0;
                final auraPoints =
                    (data['auraPoints'] as num?)?.toInt() ?? 150;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 230,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoThumbnailWidget(
                              videoUrl: videoUrl, fit: BoxFit.cover),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.4, 1.0],
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
                                const Icon(Icons.remove_red_eye_outlined,
                                    color: Colors.white70, size: 15),
                                const SizedBox(width: 4),
                                Text(_fmt(views),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                                const SizedBox(width: 12),
                                const Icon(Icons.diamond,
                                    color: Colors.redAccent, size: 13),
                                const SizedBox(width: 4),
                                Text('$auraPoints',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChallengeDetail(
                                        title: title,
                                        instructions: data['instructions'] as String? ?? '',
                                        videoUrl: videoUrl,
                                        challengeId: challengeId,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      'Take this Challenge',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
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
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ── Brand Tools (brand/admin only) ─────────────────────────────────────────
  Widget _buildBrandTools(
      BuildContext context, String userId, bool isBrand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Tools',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _toolButton(
                  label: isBrand ? 'Brand Home' : 'Start Brand Page',
                  colors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  onTap: () async {
                    final doc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .get();
                    final alreadyBrand =
                        (doc.data() ?? {})['isCreator'] ?? false;
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => alreadyBrand
                            ? const CreatorHomeScreen()
                            : const CreateCreatorProfileScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toolButton(
                  label: 'Brand Admin',
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
                  fontSize: 14)),
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
                  fontSize: 13)),
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
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  icon: Icons.sports_esports_outlined,
                  label: 'Challenges',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AllGeneralChallengesScreen()),
                  ),
                ),
                _navItem(
                  icon: Icons.store_outlined,
                  label: 'Brand\nChallenges',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BrandChallengesScreen()),
                  ),
                ),
                const SizedBox(width: 64),
                _navItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'Leaderboard',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen()),
                  ),
                ),
                _navItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MyAccountScreen()),
                  ),
                ),
              ],
            ),
            // Centre floating button
            Positioned(
              top: -22,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeFeedScreen()),
                ),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(
                      color: _accent.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0xFF7B2CBF),
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        'assets/images/Aura Arena Mono.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _thumbnailCard({
    required BuildContext context,
    required String videoUrl,
    required String title,
    required double height,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1.0],
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 7,
                right: 7,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

