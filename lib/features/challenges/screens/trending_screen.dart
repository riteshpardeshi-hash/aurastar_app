import 'package:flutter/material.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'challenge_detail.dart';

class TrendingScreen extends StatefulWidget {
  const TrendingScreen({super.key});

  @override
  State<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends State<TrendingScreen>
    with SingleTickerProviderStateMixin {
  static const _bg     = Color(0xFF0D0D1A);
  static const _card   = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  static const _tabs = ['Now', 'Today', 'Week'];

  late final TabController _tabCtrl;

  // Sort mode: 'joined' | 'liked'
  String _sort = 'joined';

  // Cache keyed by sort mode (tabs share same ranked list — API has no time window)
  final Map<String, List<_TrendingItem>> _cache   = {};
  final Map<String, bool>                _loading = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);
    _loadTab(0);
  }

  @override
  void dispose() {
    _tabCtrl
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) return;
    _loadTab(_tabCtrl.index);
  }

  String _cacheKey(int tab, String sort) => sort;

  // ── Data ──────────────────────────────────────────────────────────────────

  String _windowLabel(int tab) {
    switch (tab) {
      case 0:  return 'in the last 6 hours';
      case 1:  return 'today';
      default: return 'this week';
    }
  }

  Future<void> _loadTab(int tab) async {
    final key = _cacheKey(tab, _sort);
    if (_cache.containsKey(key)) return;
    setState(() => _loading[key] = true);

    final items = _sort == 'liked'
        ? await _fetchMostLiked()
        : await _fetchMostJoined();

    if (mounted) {
      setState(() {
        _cache[key]   = items;
        _loading[key] = false;
      });
    }
  }

  Future<List<_TrendingItem>> _fetchMostJoined() async {
    try {
      final raw = await ChallengesService().fetchChallenges(limit: 40);
      final normalised = raw.map(normaliseChallenge).toList()
        ..sort((a, b) =>
            ((b['submissionsCount'] as int?) ?? 0)
                .compareTo((a['submissionsCount'] as int?) ?? 0));
      return normalised.take(15).map((c) => _TrendingItem(
            challengeId:  c['id'] as String? ?? '',
            data:         c,
            attemptCount: c['submissionsCount'] as int? ?? 0,
            starsCount:   c['starsCount'] as int? ?? 0,
          )).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<_TrendingItem>> _fetchMostLiked() async {
    try {
      final raw = await ChallengesService().fetchChallenges(limit: 40);
      final normalised = raw.map(normaliseChallenge).toList()
        ..sort((a, b) =>
            ((b['starsCount'] as int?) ?? 0)
                .compareTo((a['starsCount'] as int?) ?? 0));
      return normalised.take(15).map((c) => _TrendingItem(
            challengeId:  c['id'] as String? ?? '',
            data:         c,
            attemptCount: c['submissionsCount'] as int? ?? 0,
            starsCount:   c['starsCount'] as int? ?? 0,
          )).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.local_fire_department_rounded,
                color: Color(0xFFFF6B35), size: 22),
            SizedBox(width: 8),
            Text('Trending',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(94),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Time tabs ────────────────────────────────────────────────
              TabBar(
                controller: _tabCtrl,
                indicatorColor: _accent,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                dividerColor: Colors.transparent,
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              ),

              // ── Sort toggle ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    _SortPill(
                      icon: Icons.group_rounded,
                      label: 'Most Joined',
                      selected: _sort == 'joined',
                      onTap: () => _onSortChanged('joined'),
                    ),
                    const SizedBox(width: 10),
                    _SortPill(
                      icon: Icons.favorite_rounded,
                      label: 'Most Liked',
                      selected: _sort == 'liked',
                      onTap: () => _onSortChanged('liked'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(_tabs.length, (i) => _buildTab(i)),
      ),
    );
  }

  void _onSortChanged(String sort) {
    if (_sort == sort) return;
    setState(() {
      _sort = sort;
      _cache.remove(sort);
    });
    _loadTab(_tabCtrl.index);
  }

  Widget _buildTab(int tab) {
    final key   = _cacheKey(tab, _sort);
    final items = _cache[key];

    if (_loading[key] == true || items == null) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    if (items.isEmpty) return _buildEmpty();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildCard(items[i], i, tab),
    );
  }

  // ── Trending card ─────────────────────────────────────────────────────────

  Widget _buildCard(_TrendingItem item, int index, int tab) {
    final title        = item.data['title']        as String? ?? '';
    final videoUrl     = item.data['videoUrl']     as String? ?? '';
    final instructions = item.data['instructions'] as String? ?? '';
    final category     = item.data['category']     as String? ?? '';
    final isTop3       = index < 3;

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChallengeDetail(
              title: title,
              instructions: instructions,
              videoUrl: videoUrl,
              challengeId: item.challengeId,
            ),
          )),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTop3
                ? _accent.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: isTop3
              ? [
                  BoxShadow(
                      color: _accent.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Row(
          children: [
            // Rank + thumbnail
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  child: SizedBox(
                    width: 100,
                    height: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoThumbnailWidget(
                            videoUrl: videoUrl, fit: BoxFit.cover),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isTop3
                          ? _accent.withValues(alpha: 0.90)
                          : Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _rankLabel(index),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: index < 3 ? 14 : 11,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Text(category,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          const Text(' · ',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 11)),
                        ],
                        const Icon(Icons.star_rounded, color: _accent, size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${item.starsCount}',
                          style: const TextStyle(
                              color: Color(0xFFD4A8FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_sort == 'joined' && item.attemptCount > 0)
                      _StatRow(
                        icon: Icons.people_outline_rounded,
                        color: const Color(0xFFFF6B35),
                        text:
                            '${_fmt(item.attemptCount)} joined ${_windowLabel(tab)}',
                      )
                    else if (_sort == 'liked' && item.starsCount > 0)
                      _StatRow(
                        icon: Icons.favorite_rounded,
                        color: const Color(0xFFFF6B9D),
                        text:
                            '${_fmt(item.starsCount)} likes ${_windowLabel(tab)}',
                      ),
                  ],
                ),
              ),
            ),

            // Take button
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChallengeDetail(
                        title: title,
                        instructions: instructions,
                        videoUrl: videoUrl,
                        challengeId: item.challengeId,
                      ),
                    )),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Take',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
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
          Icon(Icons.local_fire_department_outlined,
              color: Colors.white24, size: 52),
          SizedBox(height: 16),
          Text('Nothing trending yet',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _rankLabel(int i) {
    switch (i) {
      case 0:  return '🥇';
      case 1:  return '🥈';
      case 2:  return '🥉';
      default: return '${i + 1}';
    }
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _TrendingItem {
  final String challengeId;
  final Map<String, dynamic> data;
  final int attemptCount;
  final int starsCount;

  const _TrendingItem({
    required this.challengeId,
    required this.data,
    required this.attemptCount,
    required this.starsCount,
  });
}

// ── Sort pill ─────────────────────────────────────────────────────────────────

class _SortPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _accent.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? _accent.withValues(alpha: 0.70)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Colors.white : Colors.white38,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat row ──────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _StatRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
