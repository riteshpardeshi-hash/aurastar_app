import 'package:flutter/material.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/category_icon_badge.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'challenge_detail.dart';

class TrendingScreen extends StatefulWidget {
  const TrendingScreen({super.key});

  @override
  State<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends State<TrendingScreen> {
  static const _bg = Color(0xFF0D0D1A);
  static const _card = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  List<_TrendingItem>? _items;
  bool _loading = true;

  Map<String, String> _categoryNames = {};

  @override
  void initState() {
    super.initState();
    _load();
    ChallengesService().fetchCategoryNameMap().then((names) {
      if (mounted) setState(() => _categoryNames = names);
    });
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  // Ranked by most-joined (submissionsCount) — the only ranking this screen
  // shows now that the time-window tabs and sort toggle are gone.

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _fetchMostJoined();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<List<_TrendingItem>> _fetchMostJoined() async {
    try {
      final raw = await ChallengesService().fetchChallenges(limit: 40);
      final normalised =
          raw.map(normaliseChallenge).toList()..sort(
            (a, b) => ((b['submissionsCount'] as int?) ?? 0).compareTo(
              (a['submissionsCount'] as int?) ?? 0,
            ),
          );
      return normalised
          .take(15)
          .map(
            (c) => _TrendingItem(
              challengeId: c['id'] as String? ?? '',
              data: c,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const AppBottomNav(),
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: Color(0xFFFF6B35),
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Trending'),
          ],
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _items;
    if (_loading || items == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (items.isEmpty) return _buildEmpty();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) => _buildCard(items[i], i),
    );
  }

  // ── Trending card ─────────────────────────────────────────────────────────

  Widget _buildCard(_TrendingItem item, int index) {
    final title = item.data['title'] as String? ?? '';
    final videoUrl = item.data['videoUrl'] as String? ?? '';
    final thumbnailUrl = item.data['thumbnailUrl'] as String? ?? '';
    final instructions = item.data['instructions'] as String? ?? '';
    final categoryId = item.data['category'] as String? ?? '';
    final isTop3 = index < 3;

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
                    challengeId: item.challengeId,
                  ),
            ),
          ),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isTop3
                    ? _accent.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow:
              isTop3
                  ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                  : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoThumbnailWidget(
                videoUrl: videoUrl,
                thumbnailUrl: thumbnailUrl,
                fit: BoxFit.cover,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.5, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: CategoryIconBadge(
                  categoryName: _categoryNames[categoryId],
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            color: Colors.white24,
            size: 52,
          ),
          SizedBox(height: 16),
          Text(
            'Nothing trending yet',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Check back soon — the leaderboard heats up fast.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ],
      ),
    );
  }

}

// ── Data model ────────────────────────────────────────────────────────────────

class _TrendingItem {
  final String challengeId;
  final Map<String, dynamic> data;

  const _TrendingItem({required this.challengeId, required this.data});
}

