import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../features/search/search_screen.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'challenge_detail.dart';
import 'category_challenges_screen.dart';
import 'all_categories_screen.dart';

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

  List<Map<String, dynamic>>? _challenges;
  bool _loading = false;

  // Pagination — GET /challenges is paged server-side (`page`/`limit`); the
  // grid fetches the next page as the user nears the bottom instead of
  // loading everything up front.
  static const _pageSize = 20;
  final _scrollController = ScrollController();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  // {_id, name} pairs — GET /challenges' `category` filter is the
  // category's ObjectId, not its display name.
  List<Map<String, dynamic>> _categories = const [];
  // A random 6-category subset shown in this screen's grid — the full list
  // is one tap away via "See All", so this just teases a sample. Picked
  // once when categories load, not recomputed on every rebuild, so the
  // tiles don't reshuffle on unrelated rebuilds.
  List<Map<String, dynamic>> _displayedCategories = const [];

  @override
  void initState() {
    super.initState();
    _loadChallenges();
    _loadCategories();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    final cats = await ChallengesService().fetchCategoriesWithIds();
    if (mounted && cats.isNotEmpty) {
      final shuffled = List<Map<String, dynamic>>.from(cats)..shuffle();
      setState(() {
        _categories = cats;
        _displayedCategories = shuffled.take(6).toList();
      });
    }
  }

  Future<void> _loadChallenges() async {
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    try {
      final raw = await ChallengesService().fetchChallenges(
        page: _page,
        limit: _pageSize,
      );
      final list = raw.map(normaliseChallenge).toList();
      if (mounted)
        setState(() {
          _challenges = list;
          _hasMore = list.length == _pageSize;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _challenges = [];
          _loading = false;
          _hasMore = false;
        });
    }
  }

  // Once the backend runs out of pages (`_hasMore` false), the next load
  // wraps back to page 1 instead of stopping — the grid is meant to scroll
  // forever, cycling back through the same challenges rather than hitting a
  // dead end.
  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _hasMore ? _page + 1 : 1;
      final raw = await ChallengesService().fetchChallenges(
        page: nextPage,
        limit: _pageSize,
      );
      final list = raw.map(normaliseChallenge).toList();
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _challenges = [...?_challenges, ...list];
        _hasMore = list.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
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
              controller: _scrollController,
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
                SliverToBoxAdapter(child: _buildCategoriesSection(context)),
                _buildChallengeSliver(context),
                if (_loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _accent,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          const AppBottomNav(activeTab: AppNavTab.search),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12122A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.40),
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Search',
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 15,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ],
        ),
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
              const Text('Categories', style: AppTextStyles.sectionHeader),
              GestureDetector(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => AllCategoriesScreen(categories: _categories),
                      ),
                    ),
                child: const Text(
                  'See All >',
                  style: TextStyle(
                    color: Color(0xFF9B4DCA),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
            children:
                _displayedCategories
                    .map(
                      (cat) => _CategoryTile(
                        categoryId: cat['_id'] as String? ?? '',
                        categoryName: cat['name'] as String? ?? '',
                      ),
                    )
                    .toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Challenge grid ─────────────────────────────────────────────────────────
  Widget _buildChallengeSliver(BuildContext context) {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(color: _accent)),
        ),
      );
    }
    final list = _challenges ?? [];
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              'No challenges yet',
              style: TextStyle(color: AppColors.textFaint),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.68,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final c = list[i];
          return _ChallengeCard(
            challengeId: c['id'] as String,
            title: c['title'] as String,
            videoUrl: c['videoUrl'] as String,
            thumbnailUrl: c['thumbnailUrl'] as String? ?? '',
            instructions: c['instructions'] as String,
          );
        }, childCount: list.length),
      ),
    );
  }

}

// ── Category tile ──────────────────────────────────────────────────────────────
// Same tinted-purple styling as AllCategoriesScreen's tiles — no
// per-category video thumbnail, so all tiles render identically regardless
// of whether that category has any challenges yet.
class _CategoryTile extends StatelessWidget {
  static const _tileColor = Color(0xFF7B2CBF);

  final String categoryId;
  final String categoryName;
  const _CategoryTile({required this.categoryId, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final iconAsset = categoryIconAsset[categoryName];
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => CategoryChallengesScreen(
                    categoryId: categoryId,
                    categoryName: categoryName,
                  ),
            ),
          ),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: _tileColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _tileColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            iconAsset != null
                ? SvgPicture.asset(
                  iconAsset,
                  width: 42,
                  height: 42,
                  colorFilter: const ColorFilter.mode(
                    _tileColor,
                    BlendMode.srcIn,
                  ),
                )
                : const Icon(
                  Icons.category_rounded,
                  color: _tileColor,
                  size: 36,
                ),
            const SizedBox(height: 6),
            Text(
              categoryName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _tileColor,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Challenge card (tall, full-width) ─────────────────────────────────────────
class _ChallengeCard extends StatelessWidget {
  final String challengeId, title, videoUrl, thumbnailUrl, instructions;

  const _ChallengeCard({
    required this.challengeId,
    required this.title,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.instructions,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => ChallengeDetail(
                    title: title,
                    instructions: instructions,
                    videoUrl: videoUrl,
                    challengeId: challengeId,
                  ),
            ),
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: thumbnailUrl.isNotEmpty
            ? Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, __, ___) => VideoThumbnailWidget(
                      videoUrl: videoUrl,
                      fit: BoxFit.cover,
                    ),
              )
            : VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
      ),
    );
  }
}
