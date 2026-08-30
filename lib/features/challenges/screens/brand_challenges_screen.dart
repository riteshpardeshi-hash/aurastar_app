import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/aura_score_badge.dart';
import '../../../shared/widgets/category_icon_badge.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../core/utils/cdn_url.dart';
import '../../search/search_screen.dart';
import '../../explore/screens/creator_profile_screen.dart';
import 'challenge_detail.dart';

class BrandChallengesScreen extends StatefulWidget {
  const BrandChallengesScreen({super.key});

  @override
  State<BrandChallengesScreen> createState() => _BrandChallengesScreenState();
}

class _BrandChallengesScreenState extends State<BrandChallengesScreen> {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  static const _categories = [
    'All',
    'Fashion',
    'Dance',
    'Fitness',
    'Sports',
    'Comedy',
    'Skill',
  ];
  int _selectedCat = 0;

  // brand user data keyed by creatorId
  final Map<String, Map<String, dynamic>> _brandCache = {};

  // ── Brand data batch fetch ────────────────────────────────────────────────

  Future<void> _loadBrandData(List<QueryDocumentSnapshot> docs) async {
    final newIds =
        docs
            .map(
              (d) =>
                  (d.data() as Map<String, dynamic>)['creatorId'] as String? ??
                  '',
            )
            .where(
              (id) =>
                  id.isNotEmpty &&
                  id != 'system' &&
                  !_brandCache.containsKey(id),
            )
            .toSet()
            .toList();
    if (newIds.isEmpty) {
      return;
    }

    final snap =
        await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: newIds.take(30).toList())
            .get();

    if (mounted) {
      setState(() {
        for (final d in snap.docs) {
          _brandCache[d.id] = d.data();
        }
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<QueryDocumentSnapshot> _filtered(List<QueryDocumentSnapshot> all) {
    if (_selectedCat == 0) return all;
    final cat = _categories[_selectedCat];
    return all.where((d) {
      final c = (d.data() as Map<String, dynamic>)['category'] as String? ?? '';
      return c.toLowerCase() == cat.toLowerCase();
    }).toList();
  }

  String _brandName(String creatorId) {
    final d = _brandCache[creatorId];
    if (d == null) return 'Brand';
    return d['pageName'] as String? ?? d['name'] as String? ?? 'Brand';
  }

  String _brandInitial(String creatorId) {
    final n = _brandName(creatorId);
    return n.isNotEmpty ? n[0].toUpperCase() : 'B';
  }

  bool _isNew(dynamic createdAt) {
    if (createdAt == null) return false;
    try {
      final ts = createdAt as Timestamp;
      return DateTime.now().difference(ts.toDate()).inDays <= 14;
    } catch (_) {
      return false;
    }
  }

  bool _isHot(Map<String, dynamic> data) =>
      ((data['starsCount'] as num?)?.toInt() ?? 0) >= 5;

  void _openChallenge(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChallengeDetail(
              title: data['title'] as String? ?? '',
              instructions: data['instructions'] as String? ?? '',
              videoUrl: data['videoUrl'] as String? ?? '',
              challengeId: doc.id,
            ),
      ),
    );
  }

  void _openBrand(String creatorId) {
    if (creatorId.isEmpty || creatorId == 'system') return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorProfileScreen(creatorId: creatorId),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('challenges')
                .where('creatorId', isNotEqualTo: 'system')
                .where('status', isEqualTo: 'approved')
                .limit(40)
                .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }

          final all = snap.data?.docs ?? [];
          if (all.isNotEmpty) _loadBrandData(all);
          final docs = _filtered(all);

          return Column(
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
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            _buildSearchBar(context),
                            const SizedBox(height: 10),
                            _buildCategoryChips(),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildHero(context, docs)),
                    SliverToBoxAdapter(child: _buildFeaturedBrands()),
                    SliverToBoxAdapter(
                      child: _buildAllChallenges(context, docs),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
              const AppBottomNav(),
            ],
          );
        },
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Search brand challenges…',
              style: TextStyle(color: AppColors.textFaint, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category chips ────────────────────────────────────────────────────────

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final active = i == _selectedCat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCat = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: active ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: active ? _accent : Colors.white24),
              ),
              child: Text(
                _categories[i],
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Hero card ─────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return const SizedBox.shrink();
    final doc = docs.first;
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    // This screen still reads live Firestore rather than the REST API, so
    // there's no documented schema to confirm this field against — same
    // defensive "try it, fall back gracefully if absent" reasoning as
    // normaliseCreatorVideo's thumbnailUrl.
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final creatorId = data['creatorId'] as String? ?? '';
    final isNew = _isNew(data['createdAt']);
    final isHot = _isHot(data);
    final endLabel = campaignEndLabel(data['endDate']);
    final endColor = campaignEndColor(data['endDate']);
    final category = data['category'] as String?;

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
                VideoThumbnailWidget(
                    videoUrl: videoUrl,
                    thumbnailUrl: thumbnailUrl,
                    fit: BoxFit.cover),
                // Gradient
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
                // Badges top-left
                Positioned(
                  top: 12,
                  left: 12,
                  child: Wrap(
                    spacing: 6,
                    children: [
                      _badge('Sponsored', const Color(0xFF4B6EF6)),
                      if (isNew) _badge('New', Colors.greenAccent),
                      if (isHot) _badge('Hot 🔥', const Color(0xFFFF6B35)),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: CategoryIconBadge(categoryName: category),
                ),
                // Bottom content
                Positioned(
                  left: 16,
                  bottom: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brand attribution
                      if (creatorId.isNotEmpty)
                        GestureDetector(
                          onTap: () => _openBrand(creatorId),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _brandAvatar(creatorId, 18),
                              const SizedBox(width: 6),
                              Text(
                                _brandName(creatorId),
                                style: const TextStyle(
                                  color: Color(0xFFD4A8FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
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
                      const SizedBox(height: 6),
                      const AuraScoreBadge(),
                      if (endLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: endColor,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              endLabel,
                              style: TextStyle(
                                color: endColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
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

  // ── Featured brands strip ─────────────────────────────────────────────────

  Widget _buildFeaturedBrands() {
    if (_brandCache.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Featured Brands',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children:
                _brandCache.entries.map((e) {
                  final data = e.value;
                  final pageName =
                      data['pageName'] as String? ??
                      data['name'] as String? ??
                      'Brand';
                  final imgUrl = data['profileImageUrl'] as String? ?? '';

                  return GestureDetector(
                    onTap: () => _openBrand(e.key),
                    child: Container(
                      width: 64,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                            child:
                                imgUrl.isNotEmpty
                                    ? ClipOval(
                                      child: Image.network(
                                        imgUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : Center(
                                      child: Text(
                                        pageName.isNotEmpty
                                            ? pageName[0].toUpperCase()
                                            : 'B',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            pageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── All challenges grid ───────────────────────────────────────────────────

  Widget _buildAllChallenges(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) {
    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.store_outlined, color: Colors.white24, size: 52),
            const SizedBox(height: 16),
            Text(
              _selectedCat > 0
                  ? 'No ${_categories[_selectedCat]} brand challenges yet'
                  : 'No brand challenges yet',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 15),
            ),
          ],
        ),
      );
    }

    // skip first doc — already shown in hero
    final gridDocs = docs.length > 1 ? docs.sublist(1) : docs;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemCount: gridDocs.length,
        itemBuilder: (context, i) => _buildCard(context, gridDocs[i]),
      ),
    );
  }

  Widget _buildCard(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = data['title'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final creatorId = data['creatorId'] as String? ?? '';
    final isNew = _isNew(data['createdAt']);
    final isHot = _isHot(data);
    final endLabel = campaignEndLabel(data['endDate']);
    final endColor = campaignEndColor(data['endDate']);
    final category = data['category'] as String?;

    return GestureDetector(
      onTap: () => _openChallenge(context, doc),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnailWidget(
                        videoUrl: videoUrl,
                        thumbnailUrl: thumbnailUrl,
                        fit: BoxFit.cover),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Badges
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          _badge('Sponsored', const Color(0xFF4B6EF6)),
                          if (isNew) _badge('New', Colors.green),
                          if (isHot) _badge('Hot', const Color(0xFFFF6B35)),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: CategoryIconBadge(
                        categoryName: category,
                        size: 26,
                      ),
                    ),
                    const Positioned(
                      bottom: 7,
                      left: 7,
                      child: AuraScoreBadge(),
                    ),
                  ],
                ),
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      // Brand avatar + name
                      if (creatorId.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () => _openBrand(creatorId),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _brandAvatar(creatorId, 14),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 60),
                                child: Text(
                                  _brandName(creatorId),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD4A8FF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (endLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, color: endColor, size: 9),
                          const SizedBox(width: 3),
                          Text(
                            endLabel,
                            style: TextStyle(
                              color: endColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _brandAvatar(String creatorId, double size) {
    final data = _brandCache[creatorId];
    final imgUrl = data?['profileImageUrl'] as String? ?? '';
    final initial = _brandInitial(creatorId);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child:
          imgUrl.isNotEmpty
              ? ClipOval(child: Image.network(imgUrl, fit: BoxFit.cover))
              : Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.55,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
    );
  }

}
