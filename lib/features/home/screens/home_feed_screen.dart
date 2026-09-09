import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../features/challenges/screens/challenge_detail.dart';
import '../../../features/challenges/screens/all_categories_screen.dart' show categoryIconAsset;
import '../../../features/challenges/screens/all_general_challenges_screen.dart';
import '../../../features/challenges/screens/category_challenges_screen.dart';
import '../../../features/challenges/screens/trending_screen.dart';
import '../../../features/explore/screens/brand_profile_screen.dart';
import '../../../features/explore/screens/creator_profile_screen.dart';
import '../../../features/explore/screens/explore_creators_screen.dart';
import '../../../features/search/search_screen.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/home_service.dart';
import '../../../core/services/video_prewarm_cache.dart';
import '../../../core/utils/cdn_url.dart';
import '../../../shared/widgets/notification_bell_button.dart';

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
          SliverToBoxAdapter(child: _FeaturedHeroCard()),
          SliverToBoxAdapter(child: _BannersCarousel()),
          SliverToBoxAdapter(child: _BrandChallengesShelf()),
          SliverToBoxAdapter(child: _TrendingCreatorsShelf()),
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
      actions: const [
        NotificationBellButton(),
        SizedBox(width: 4),
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
                  color: AppColors.textFaint, fontSize: 14),
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
  String? thumbnailUrl,
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
            VideoThumbnailWidget(
                videoUrl: videoUrl,
                thumbnailUrl: thumbnailUrl,
                fit: BoxFit.cover),
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

// ── Featured Hero Card ─────────────────────────────────────────────────────────

class _FeaturedHeroCard extends StatefulWidget {
  @override
  State<_FeaturedHeroCard> createState() => _FeaturedHeroCardState();
}

class _FeaturedHeroCardState extends State<_FeaturedHeroCard> {
  Map<String, dynamic>? _challenge;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await HomeService().fetchFeatured();
    if (mounted) setState(() { _challenge = c; _loaded = true; });
    // The most prominent card on the whole screen — almost certainly the
    // first thing a user taps. Start loading its reference video now so
    // ChallengeDetail's own player has nothing left to wait on when it
    // opens. mixWithOthers:true matches what ChallengeDetail's player
    // itself uses — see VideoPrewarmCache.prewarm's doc comment on why
    // this has to match the eventual consumer.
    final videoUrl = c != null
        ? normaliseHomeSummary(c)['videoUrl'] as String? ?? ''
        : '';
    if (videoUrl.isNotEmpty) {
      VideoPrewarmCache.prewarm(videoUrl, mixWithOthers: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _challenge == null) return const SizedBox.shrink();
    final c = normaliseHomeSummary(_challenge!);
    const accent = Color(0xFF7B2CBF);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: c['title'] as String,
            instructions: c['instructions'] as String,
            videoUrl: c['videoUrl'] as String,
            challengeId: c['id'] as String,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0D0D20),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoThumbnailWidget(
                  videoUrl: c['videoUrl'] as String,
                  thumbnailUrl: c['thumbnailUrl'] as String?,
                  fit: BoxFit.cover),
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
              Positioned(
                top: 10,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('FEATURED', style: AppTextStyles.eyebrow),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.diamond, color: accent, size: 13),
                        const SizedBox(width: 4),
                        Text('${c['starsCount']} Aura',
                            style: const TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        if ((c['category'] as String).isNotEmpty)
                          Text(c['category'] as String,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12)),
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
  }
}

// ── Banners Carousel ───────────────────────────────────────────────────────────

class _BannersCarousel extends StatefulWidget {
  @override
  State<_BannersCarousel> createState() => _BannersCarouselState();
}

class _BannersCarouselState extends State<_BannersCarousel> {
  List<Map<String, dynamic>>? _banners;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final banners = await HomeService().fetchBanners();
    if (mounted) setState(() => _banners = banners);
  }

  @override
  Widget build(BuildContext context) {
    if (_banners == null || _banners!.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _banners!.length,
            itemBuilder: (context, i) => _bannerCard(context, _banners![i]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _bannerCard(BuildContext context, Map<String, dynamic> banner) {
    final id = banner['_id'] as String? ?? '';
    final imageUrl = banner['imageUrl'] as String? ?? '';
    final title = banner['title'] as String?;
    final subtitle = banner['subtitle'] as String?;
    final linkType = banner['linkType'] as String? ?? 'none';
    final linkId = banner['linkId'] as String?;
    final linkUrl = banner['linkUrl'] as String?;

    void onTap() {
      if (id.isNotEmpty) HomeService().registerBannerClick(id);
      switch (linkType) {
        case 'challenge':
          if (linkId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChallengeDetail(
                  title: title ?? '',
                  instructions: subtitle ?? '',
                  videoUrl: '',
                  challengeId: linkId,
                ),
              ),
            );
          }
        case 'brand':
          if (linkId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BrandProfileScreen(brandId: linkId)),
            );
          }
        case 'creator':
          if (linkId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CreatorProfileScreen(creatorId: linkId)),
            );
          }
        case 'external':
          if (linkUrl != null) {
            final uri = Uri.tryParse(linkUrl);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          }
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0D0D20),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1A1A2E),
                    child: const Icon(Icons.image_outlined,
                        color: Colors.white24, size: 32),
                  ),
                )
              else
                Container(color: const Color(0xFF1A1A2E)),
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
              if (title != null || subtitle != null)
                Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      if (subtitle != null)
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Brand Challenges Shelf ─────────────────────────────────────────────────────

class _BrandChallengesShelf extends StatefulWidget {
  @override
  State<_BrandChallengesShelf> createState() => _BrandChallengesShelfState();
}

class _BrandChallengesShelfState extends State<_BrandChallengesShelf> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await HomeService().fetchBrandChallenges(limit: 10);
      final items = docs.map(normaliseHomeSummary).toList();
      if (mounted) setState(() => _items = items);
      // Only the first card of this horizontal shelf — prewarming every
      // card in every shelf would just thrash VideoPrewarmCache's small
      // cap for videos the user hasn't scrolled to yet.
      if (items.isNotEmpty) {
        final videoUrl = items.first['videoUrl'] as String? ?? '';
        if (videoUrl.isNotEmpty) {
          VideoPrewarmCache.prewarm(videoUrl, mixWithOthers: true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

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
        if (_items == null)
          _loadingShelf()
        else if (_items!.isEmpty)
          _emptyShelf('No brand challenges yet')
        else
          _horizontalList(
            _items!.map((c) => _challengeCard(
              context,
              c['id'] as String,
              c['title'] as String,
              c['instructions'] as String,
              c['videoUrl'] as String,
              c['starsCount'] as int,
              thumbnailUrl: c['thumbnailUrl'] as String?,
              badge: 'BRAND',
              badgeColor: const Color(0xFFE040FB),
            )).toList(),
          ),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ── Trending Creators Shelf ────────────────────────────────────────────────────

class _TrendingCreatorsShelf extends StatefulWidget {
  @override
  State<_TrendingCreatorsShelf> createState() => _TrendingCreatorsShelfState();
}

class _TrendingCreatorsShelfState extends State<_TrendingCreatorsShelf> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final creators = await HomeService().fetchTrendingCreators(limit: 10);
      if (mounted) setState(() => _items = creators);
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          context,
          'Trending Creators',
          'Top creators this week',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ExploreCreatorsScreen())),
        ),
        if (_items == null)
          _loadingShelf()
        else if (_items!.isEmpty)
          _emptyShelf('No creators yet')
        else
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: _items!.map((c) => _creatorCard(c)).toList(),
            ),
          ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _creatorCard(Map<String, dynamic> creator) {
    final name = creator['displayName'] as String? ?? '';
    final avatar = creator['avatar'] as String?;
    final aura = (creator['auraPoints'] as num?)?.toInt() ?? 0;

    return Container(
      width: 90,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF1A1A2E),
            backgroundImage:
                avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar == null || avatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white54, size: 28)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.diamond, color: Color(0xFF7B2CBF), size: 10),
              const SizedBox(width: 2),
              Text(
                _fmtAura(aura),
                style: const TextStyle(
                    color: Color(0xFFD4A8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtAura(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Categories Section ─────────────────────────────────────────────────────────

class _CategoriesSection extends StatefulWidget {
  const _CategoriesSection();

  @override
  State<_CategoriesSection> createState() => _CategoriesSectionState();
}

class _CategoriesSectionState extends State<_CategoriesSection> {
  static const _accent = Color(0xFF7B2CBF);

  List<Map<String, dynamic>>? _categories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await ChallengesService().fetchCategoriesWithIds();
    if (mounted) setState(() => _categories = cats);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Browse by Category', style: AppTextStyles.sectionHeader),
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
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final id = categories[i]['_id'] as String? ?? '';
              final name = categories[i]['name'] as String? ?? '';
              final iconAsset = categoryIconAsset[name];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryChallengesScreen(
                        categoryId: id, categoryName: name),
                  ),
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      iconAsset != null
                          ? SvgPicture.asset(
                              iconAsset,
                              width: 28,
                              height: 28,
                              colorFilter: const ColorFilter.mode(
                                  _accent, BlendMode.srcIn),
                            )
                          : const Icon(Icons.category_rounded,
                              color: _accent, size: 28),
                      const SizedBox(height: 5),
                      Text(name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _accent,
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
    try {
      final docs = await HomeService().fetchTrending(limit: 8);
      final items = docs
          .map(normaliseHomeSummary)
          .map((c) => _TrendDoc(
                c['id'] as String,
                c,
                (c['submissionsCount'] as int?) ?? 0,
              ))
          .toList();
      if (mounted) setState(() => _items = items);
      // Only the first card — see the same note on _BrandChallengesShelf.
      if (items.isNotEmpty) {
        final videoUrl = items.first.data['videoUrl'] as String? ?? '';
        if (videoUrl.isNotEmpty) {
          VideoPrewarmCache.prewarm(videoUrl, mixWithOthers: true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
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
                (d['starsCount'] as int?) ?? 0,
                thumbnailUrl: d['thumbnailUrl'] as String?,
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
