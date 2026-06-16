import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../features/challenges/screens/challenge_detail.dart';
import '../../../features/challenges/screens/all_general_challenges_screen.dart';
import '../../../features/challenges/screens/category_challenges_screen.dart';
import '../../../features/challenges/screens/trending_screen.dart';
import '../../../features/explore/screens/explore_creators_screen.dart';
import '../../../features/notifications/notifications_screen.dart';
import '../../../features/search/search_screen.dart';
import '../../../core/utils/cdn_url.dart';

class HomeFeedScreen extends StatelessWidget {
  const HomeFeedScreen({super.key});

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(child: _buildSearchBar(context)),
          SliverToBoxAdapter(child: _BrandChallengesShelf()),
          SliverToBoxAdapter(child: _CreatorVideosShelf()),
          SliverToBoxAdapter(child: _CategoriesSection()),
          SliverToBoxAdapter(child: _TrendingShelf()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: _bg,
      floating: true,
      snap: true,
      elevation: 0,
      titleSpacing: 16,
      title: Image.asset('assets/images/Aura arena.png', height: 20,
          alignment: Alignment.centerLeft),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white70),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF111122),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                color: Colors.white.withValues(alpha: 0.35), size: 20),
            const SizedBox(width: 10),
            Text(
              'Search challenges, brands, creators…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.30), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

Widget _sectionHeader(
  BuildContext context,
  String title,
  String subtitle,
  VoidCallback onSeeAll,
) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.40),
                      fontSize: 11)),
          ],
        ),
        const Spacer(),
        GestureDetector(
          onTap: onSeeAll,
          child: Text('See all',
              style: TextStyle(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Widget _challengeCard(
  BuildContext context,
  String challengeId,
  String title,
  String instructions,
  String videoUrl,
  int auraPoints, {
  String? badge,
  Color? badgeColor,
  dynamic endDate,
}) {
  const accent = Color(0xFF7B2CBF);
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
      width: 145,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF0D0D20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
            // Gradient overlay
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
            // Top badge
            if (badge != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? accent).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3)),
                ),
              ),
            // Bottom info
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.3),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.diamond, color: accent, size: 11),
                        const SizedBox(width: 3),
                        Text('$auraPoints',
                            style: const TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Builder(builder: (_) {
                      final label = campaignEndLabel(endDate);
                      if (label.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined,
                                color: campaignEndColor(endDate), size: 10),
                            const SizedBox(width: 3),
                            Text(label,
                                style: TextStyle(
                                    color: campaignEndColor(endDate),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }),
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

// ── Brand Challenges Shelf ─────────────────────────────────────────────────────

class _BrandChallengesShelf extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          'Brand Challenges',
          'Earn offers from top brands',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AllGeneralChallengesScreen())),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .where('creatorId', isNotEqualTo: 'system')
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return _loadingShelf();
            }
            if (docs.isEmpty) return _emptyShelf('No brand challenges yet');
            return _horizontalList(
              docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return _challengeCard(
                  context,
                  doc.id,
                  d['title'] as String? ?? '',
                  d['instructions'] as String? ?? '',
                  d['videoUrl'] as String? ?? '',
                  (d['auraPoints'] as num?)?.toInt() ?? 100,
                  badge: 'BRAND',
                  badgeColor: const Color(0xFFE040FB),
                  endDate: d['endDate'],
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ── Creator Videos Shelf ───────────────────────────────────────────────────────

class _CreatorVideosShelf extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          'Creator Videos',
          'Challenges by the community',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ExploreCreatorsScreen())),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .where('creatorId', isEqualTo: 'system')
              .limit(10)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (snap.connectionState == ConnectionState.waiting) {
              return _loadingShelf();
            }
            if (docs.isEmpty) return _emptyShelf('No challenges yet');
            return _horizontalList(
              docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return _challengeCard(
                  context,
                  doc.id,
                  d['title'] as String? ?? '',
                  d['instructions'] as String? ?? '',
                  d['videoUrl'] as String? ?? '',
                  (d['auraPoints'] as num?)?.toInt() ?? 100,
                  badge: 'FEATURED',
                  badgeColor: const Color(0xFF7B2CBF),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ── Categories Section ─────────────────────────────────────────────────────────

class _CategoriesSection extends StatelessWidget {
  static const _categories = <String, ({IconData icon, Color color})>{
    'Dance':   (icon: Icons.music_note_rounded,        color: Color(0xFF4B6EF6)),
    'Fitness': (icon: Icons.fitness_center_rounded,    color: Color(0xFF22C55E)),
    'Fashion': (icon: Icons.checkroom_rounded,         color: Color(0xFFFF6B9D)),
    'Sports':  (icon: Icons.sports_basketball_rounded, color: Color(0xFFF97316)),
    'Comedy':  (icon: Icons.mood_rounded,              color: Color(0xFFEAB308)),
    'Skill':   (icon: Icons.psychology_rounded,        color: Color(0xFF06B6D4)),
  };

  @override
  Widget build(BuildContext context) {
    final entries = _categories.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: const Text('Browse by Category',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.55,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final name = entries[i].key;
              final meta = entries[i].value;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryChallengesScreen(category: name),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: meta.color.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(meta.icon, color: meta.color, size: 22),
                      const SizedBox(height: 5),
                      Text(name,
                          style: TextStyle(
                              color: meta.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ── Trending Shelf ─────────────────────────────────────────────────────────────

class _TrendingShelf extends StatefulWidget {
  @override
  State<_TrendingShelf> createState() => _TrendingShelfState();
}

class _TrendingShelfState extends State<_TrendingShelf> {
  List<_TrendDoc>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final subsSnap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('status', isEqualTo: 'approved')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .limit(100)
        .get();

    final counts = <String, int>{};
    for (final doc in subsSnap.docs) {
      final cid = (doc.data())['challengeId'] as String? ?? '';
      if (cid.isNotEmpty) counts[cid] = (counts[cid] ?? 0) + 1;
    }

    List<_TrendDoc> items;
    if (counts.isEmpty) {
      // Fallback to any challenges
      final snap = await FirebaseFirestore.instance
          .collection('challenges')
          .limit(8)
          .get();
      items = snap.docs.map((d) => _TrendDoc(d.id, d.data(), 0)).toList();
    } else {
      final ranked = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topIds = ranked.take(8).map((e) => e.key).toList();
      final chalSnap = await FirebaseFirestore.instance
          .collection('challenges')
          .where(FieldPath.documentId, whereIn: topIds)
          .get();
      final chalMap = {for (final d in chalSnap.docs) d.id: d.data()};
      items = ranked
          .take(8)
          .where((e) => chalMap.containsKey(e.key))
          .map((e) => _TrendDoc(e.key, chalMap[e.key]!, e.value))
          .toList();
    }

    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          'Trending Now 🔥',
          'Most played in the last 24 hours',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TrendingScreen())),
        ),
        if (_items == null)
          _loadingShelf()
        else if (_items!.isEmpty)
          _emptyShelf('Nothing trending yet')
        else
          _horizontalList(
            _items!.map((item) {
              final d = item.data;
              return _challengeCard(
                context,
                item.challengeId,
                d['title'] as String? ?? '',
                d['instructions'] as String? ?? '',
                d['videoUrl'] as String? ?? '',
                (d['auraPoints'] as num?)?.toInt() ?? 100,
                badge: item.count > 0 ? '${_fmt(item.count)} plays' : null,
                badgeColor: const Color(0xFFFF6B35),
              );
            }).toList(),
          ),
        const SizedBox(height: 28),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _TrendDoc {
  final String challengeId;
  final Map<String, dynamic> data;
  final int count;
  const _TrendDoc(this.challengeId, this.data, this.count);
}

// ── Shelf layout helpers ───────────────────────────────────────────────────────

Widget _horizontalList(List<Widget> cards) {
  return SizedBox(
    height: 200,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: cards,
    ),
  );
}

Widget _loadingShelf() {
  return const SizedBox(
    height: 200,
    child: Center(
      child: CircularProgressIndicator(
        color: Color(0xFF7B2CBF),
        strokeWidth: 2,
      ),
    ),
  );
}

Widget _emptyShelf(String message) {
  return SizedBox(
    height: 80,
    child: Center(
      child: Text(message,
          style: const TextStyle(color: Colors.white24, fontSize: 13)),
    ),
  );
}
