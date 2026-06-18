import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../features/search/search_screen.dart';
import '../../../features/leaderboard/leaderboard_screen.dart';
import '../../../features/account/screens/my_account_screen.dart';
import '../../../features/explore/screens/explore_creators_screen.dart';
import '../../../shared/widgets/aura_action_sheet.dart';
import 'challenge_detail.dart';
import 'category_challenges_screen.dart';

class AllGeneralChallengesScreen extends StatefulWidget {
  const AllGeneralChallengesScreen({super.key});

  @override
  State<AllGeneralChallengesScreen> createState() =>
      _AllGeneralChallengesScreenState();
}

class _AllGeneralChallengesScreenState
    extends State<AllGeneralChallengesScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  String _filter = 'Trending';

  static const _categories = [
    'Dance',
    'Fitness',
    'Fashion',
    'Sports',
    'Comedy',
    'Skill',
  ];
  static const _filters = ['Trending', 'New', 'Easy', 'High Aura'];

  Query<Map<String, dynamic>> get _challengeQuery {
    final base =
        FirebaseFirestore.instance.collection('challenges');
    switch (_filter) {
      case 'New':
        return base.orderBy('createdAt', descending: true).limit(10);
      case 'High Aura':
        return base.orderBy('auraPoints', descending: true).limit(10);
      case 'Easy':
        return base
            .where('difficulty', isEqualTo: 'easy')
            .limit(10);
      default:
        return base.limit(10);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        _buildSearchBar(context),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                    child: _buildCategoriesSection(context)),
                SliverToBoxAdapter(child: _buildFilterChips()),
                SliverToBoxAdapter(
                    child: _buildChallengeList(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.40), size: 20),
          const SizedBox(width: 10),
          Text(
            'Search',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 15,
                fontFamily: 'SpaceGrotesk'),
          ),
        ]),
      ),
    );
  }

  // ── Categories 2×3 grid ────────────────────────────────────────────────────
  Widget _buildCategoriesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Categories',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay')),
              GestureDetector(
                onTap: () {},
                child: const Text('See All >',
                    style: TextStyle(
                        color: Color(0xFF9B4DCA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 0.9,
            children: _categories
                .map((cat) => _CategoryTile(category: cat))
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Row(
        children: _filters.map((f) {
          final active = f == _filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active
                          ? _accent
                          : Colors.white.withValues(alpha: 0.20)),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color:
                        active ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: active
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Challenge list ─────────────────────────────────────────────────────────
  Widget _buildChallengeList(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _challengeQuery.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
              height: 120,
              child: Center(
                  child:
                      CircularProgressIndicator(color: _accent)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: Text('No challenges yet',
                  style: TextStyle(color: Colors.white38)),
            ),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _ChallengeCard(
              challengeId: doc.id,
              title: data['title'] as String? ?? '',
              videoUrl: data['videoUrl'] as String? ?? '',
              thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
              auraPoints:
                  (data['auraPoints'] as num?)?.toInt() ?? 0,
              views: (data['views'] as num?)?.toInt() ?? 0,
              instructions:
                  data['instructions'] as String? ?? '',
            );
          }).toList(),
        );
      },
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
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
                        color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(
                        icon: Icons.emoji_events_rounded,
                        label: 'Challenges',
                        active: true,
                        onTap: () {},
                      ),
                      _navItem(
                        icon: Icons.storefront_rounded,
                        label: 'Brand',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ExploreCreatorsScreen()),
                        ),
                      ),
                      const SizedBox(width: 58),
                      _navItem(
                        icon: Icons.leaderboard_rounded,
                        label: 'Leaderboard',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const LeaderboardScreen()),
                        ),
                      ),
                      _navItem(
                        icon: Icons.person_rounded,
                        label: 'Profile',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const MyAccountScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: _accent.withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 1)
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Image.asset(
                          'assets/images/Aura Arena Mono.png',
                          fit: BoxFit.contain),
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
            Icon(icon,
                color: active ? _accent : Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: active ? _accent : Colors.white38,
                    fontSize: 9,
                    fontFamily: 'SpaceGrotesk',
                    height: 1.2)),
          ],
        ),
      ),
    );
  }
}

// ── Category tile (fetches first challenge in category) ────────────────────────
class _CategoryTile extends StatelessWidget {
  final String category;
  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('category', isEqualTo: category)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final data = docs.isNotEmpty
            ? docs.first.data() as Map<String, dynamic>
            : null;
        final thumbnailUrl = data?['thumbnailUrl'] as String? ?? '';
        final videoUrl = data?['videoUrl'] as String? ?? '';

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    CategoryChallengesScreen(category: category)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailUrl.isNotEmpty)
                  Image.network(thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _DarkPlaceholder())
                else if (videoUrl.isNotEmpty)
                  VideoThumbnailWidget(
                      videoUrl: videoUrl, fit: BoxFit.cover)
                else
                  const _DarkPlaceholder(),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.4, 1.0],
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 7,
                  left: 0,
                  right: 0,
                  child: Text(
                    category,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
      },
    );
  }
}

// ── Challenge card (tall, full-width) ─────────────────────────────────────────
class _ChallengeCard extends StatelessWidget {
  final String challengeId, title, videoUrl, thumbnailUrl, instructions;
  final int auraPoints, views;

  static const _accent = Color(0xFF7B2CBF);

  const _ChallengeCard({
    required this.challengeId,
    required this.title,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.instructions,
    required this.auraPoints,
    required this.views,
  });

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail
                if (thumbnailUrl.isNotEmpty)
                  Image.network(thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          VideoThumbnailWidget(
                              videoUrl: videoUrl, fit: BoxFit.cover))
                else
                  VideoThumbnailWidget(
                      videoUrl: videoUrl, fit: BoxFit.cover),
                // Bottom gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.35, 1.0],
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                // Bottom overlay
                Positioned(
                  bottom: 12,
                  left: 14,
                  right: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility_rounded,
                          color: Colors.white60, size: 14),
                      const SizedBox(width: 4),
                      Text(_fmt(views),
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontFamily: 'SpaceGrotesk')),
                      const SizedBox(width: 10),
                      const Icon(Icons.diamond_rounded,
                          color: _accent, size: 14),
                      const SizedBox(width: 4),
                      Text('$auraPoints',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SpaceGrotesk')),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Take this Challenge',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SpaceGrotesk',
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
      ),
    );
  }
}

// ── Dark placeholder for missing thumbnails ────────────────────────────────────
class _DarkPlaceholder extends StatelessWidget {
  const _DarkPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0F0F1A),
        child: const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white12, size: 36),
        ),
      );
}
