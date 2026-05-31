import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'challenge_detail.dart';
import 'all_general_challenges_screen.dart';
import '../../leaderboard/leaderboard_screen.dart';
import '../../account/screens/my_account_screen.dart';

class BrandChallengesScreen extends StatefulWidget {
  const BrandChallengesScreen({super.key});

  @override
  State<BrandChallengesScreen> createState() => _BrandChallengesScreenState();
}

class _BrandChallengesScreenState extends State<BrandChallengesScreen> {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  static const _chips = ['Action', 'Fashion', 'Dance', 'Zombie', 'Sport'];
  int _selectedChip = 0;

  static const _categorySections = [
    ('Beauty & Wellness', 'beauty'),
    ('Fashion & Lifestyle', 'fashion'),
    ('Fitness & Sports', 'fitness'),
  ];

  void _openChallenge(BuildContext ctx, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => ChallengeDetail(
          title: data['title'] as String? ?? '',
          instructions: data['instructions'] as String? ?? '',
          videoUrl: data['videoUrl'] as String? ?? '',
          challengeId: doc.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .limit(20)
            .snapshots(),
        builder: (context, snap) {
          final all = snap.data?.docs ?? [];
          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            _buildSearchBar(),
                            const SizedBox(height: 12),
                            _buildChips(),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildHero(context, all)),
                    SliverToBoxAdapter(child: _buildMostLoved(context, all)),
                    SliverToBoxAdapter(child: _buildSponsoredBanner(context, all)),
                    for (final (label, slug) in _categorySections)
                      SliverToBoxAdapter(
                        child: _buildCategorySection(context, label, slug, all),
                      ),
                    SliverToBoxAdapter(child: _buildBottomGrid(context, all)),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
              _buildBottomNav(context),
            ],
          );
        },
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            SizedBox(width: 14),
            Icon(Icons.search_rounded, color: Colors.white38, size: 20),
            SizedBox(width: 8),
            Text(
              'Search brand challenges…',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category chips ─────────────────────────────────────────────────────────
  Widget _buildChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _selectedChip;
          return GestureDetector(
            onTap: () => setState(() => _selectedChip = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? _accent : Colors.white24,
                ),
              ),
              child: Text(
                _chips[i],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Hero banner ────────────────────────────────────────────────────────────
  Widget _buildHero(BuildContext context, List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();
    final doc = docs.first;
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: GestureDetector(
        onTap: () => _openChallenge(context, doc),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.3, 1.0],
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
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
                          const Icon(Icons.diamond, color: _accent, size: 18),
                          const SizedBox(width: 5),
                          Text(
                            '$auraPoints+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.diamond_outlined,
                              color: Colors.white70, size: 10),
                          SizedBox(width: 6),
                          Icon(Icons.diamond_outlined,
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
  }

  // ── Most Loved Brands ──────────────────────────────────────────────────────
  Widget _buildMostLoved(
      BuildContext context, List<QueryDocumentSnapshot> docs) {
    final cards = docs.take(3).toList();
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Most Loved Brands'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: List.generate(cards.length, (i) {
              final doc = cards[i];
              final data = doc.data() as Map<String, dynamic>;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: _thumbCard(
                    videoUrl: data['videoUrl'] as String? ?? '',
                    title: data['title'] as String? ?? '',
                    onTap: () => _openChallenge(context, doc),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Sponsored brand banner ─────────────────────────────────────────────────
  Widget _buildSponsoredBanner(
      BuildContext context, List<QueryDocumentSnapshot> docs) {
    final doc = docs.length > 1 ? docs[1] : (docs.isNotEmpty ? docs.first : null);
    if (doc == null) return const SizedBox.shrink();
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final instructions = data['instructions'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: GestureDetector(
        onTap: () => _openChallenge(context, doc),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                // Left-heavy dark gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.6, 1.0],
                      colors: [
                        Color(0xEE000000),
                        Color(0x99000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  right: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (instructions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          instructions,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.diamond, color: _accent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$auraPoints+',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
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
    );
  }

  // ── Per-category row section ───────────────────────────────────────────────
  Widget _buildCategorySection(
    BuildContext context,
    String label,
    String slug,
    List<QueryDocumentSnapshot> all,
  ) {
    final docs = all
        .where((d) =>
            (d.data() as Map<String, dynamic>)['category'] == slug)
        .take(3)
        .toList();
    if (docs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(label),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: List.generate(docs.length, (i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: _thumbCard(
                    videoUrl: data['videoUrl'] as String? ?? '',
                    title: data['title'] as String? ?? '',
                    onTap: () => _openChallenge(context, doc),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Bottom 2-column grid ───────────────────────────────────────────────────
  Widget _buildBottomGrid(
      BuildContext context, List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.0,
        ),
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final doc = docs[i];
          final data = doc.data() as Map<String, dynamic>;
          final title = data['title'] as String? ?? '';
          final videoUrl = data['videoUrl'] as String? ?? '';
          final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;
          final instructions = data['instructions'] as String? ?? '';

          return GestureDetector(
            onTap: () => _openChallenge(context, doc),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                  Container(color: Colors.black54),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
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
                          ),
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
                              height: 1.3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.diamond, color: _accent, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              '$auraPoints+',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
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
          );
        },
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            '>>>',
            style: TextStyle(
                color: Colors.white38, fontSize: 13, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _thumbCard({
    required String videoUrl,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 110,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
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
                  active: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AllGeneralChallengesScreen()),
                  ),
                ),
                _navItem(
                  icon: Icons.store_outlined,
                  label: 'Brand\nChallenges',
                  active: true,
                  onTap: () {},
                ),
                const SizedBox(width: 64),
                _navItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'Leaderboard',
                  active: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                  ),
                ),
                _navItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  active: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyAccountScreen()),
                  ),
                ),
              ],
            ),
            Positioned(
              top: -22,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
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
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            ),
          ),
        ],
      ),
    );
  }
}
