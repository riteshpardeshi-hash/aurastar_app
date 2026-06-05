import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // results per tab
  final Map<int, List<_TrendingItem>> _results = {};
  final Map<int, bool> _loading = {};
  final Map<int, bool> _loaded  = {};

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

  // ── Data ──────────────────────────────────────────────────────────────────

  Duration _windowFor(int tab) {
    switch (tab) {
      case 0: return const Duration(hours: 6);
      case 1: return const Duration(hours: 24);
      default: return const Duration(days: 7);
    }
  }

  String _windowLabel(int tab) {
    switch (tab) {
      case 0: return 'in the last 6 hours';
      case 1: return 'today';
      default: return 'this week';
    }
  }

  Future<void> _loadTab(int tab) async {
    if (_loaded[tab] == true) return;
    setState(() => _loading[tab] = true);

    final since = DateTime.now().subtract(_windowFor(tab));
    final items = await _fetchTrending(since);

    if (mounted) {
      setState(() {
        _results[tab] = items;
        _loading[tab] = false;
        _loaded[tab]  = true;
      });
    }
  }

  Future<List<_TrendingItem>> _fetchTrending(DateTime since) async {
    // Step 1 — recent approved submissions in the window
    final subsSnap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('status',    isEqualTo: 'approved')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();

    // Step 2 — count attempts per challengeId
    final counts = <String, int>{};
    for (final doc in subsSnap.docs) {
      final cid = (doc.data())['challengeId'] as String? ?? '';
      if (cid.isNotEmpty) counts[cid] = (counts[cid] ?? 0) + 1;
    }

    // Step 3 — if no submissions in window fall back to starsCount ordering
    if (counts.isEmpty) return _fetchFallback();

    // Sort by attempt count desc, take top 15
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topIds = ranked.take(15).map((e) => e.key).toList();

    // Step 4 — fetch challenge docs (whereIn max 30, we have ≤15)
    final chalSnap = await FirebaseFirestore.instance
        .collection('challenges')
        .where(FieldPath.documentId, whereIn: topIds)
        .get();

    final chalMap = {for (final d in chalSnap.docs) d.id: d.data()};

    // Step 5 — build ranked list preserving order
    return ranked
        .take(15)
        .where((e) => chalMap.containsKey(e.key))
        .map((e) => _TrendingItem(
              challengeId:  e.key,
              data:         chalMap[e.key]!,
              attemptCount: e.value,
            ))
        .toList();
  }

  Future<List<_TrendingItem>> _fetchFallback() async {
    final snap = await FirebaseFirestore.instance
        .collection('challenges')
        .where('status', isEqualTo: 'approved')
        .orderBy('starsCount', descending: true)
        .limit(15)
        .get();

    if (snap.docs.isEmpty) {
      // Last resort — any challenges at all
      final any = await FirebaseFirestore.instance
          .collection('challenges')
          .limit(15)
          .get();
      return any.docs
          .map((d) => _TrendingItem(challengeId: d.id, data: d.data(), attemptCount: 0))
          .toList();
    }

    return snap.docs
        .map((d) => _TrendingItem(challengeId: d.id, data: d.data(), attemptCount: 0))
        .toList();
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
            Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF6B35), size: 22),
            SizedBox(width: 8),
            Text('Trending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(45),
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: _accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            dividerColor: Colors.white10,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
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

  Widget _buildTab(int tab) {
    if (_loading[tab] == true) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    final items = _results[tab];
    if (items == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
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
    final title      = item.data['title']      as String? ?? '';
    final videoUrl   = item.data['videoUrl']   as String? ?? '';
    final instructions = item.data['instructions'] as String? ?? '';
    final auraPoints = (item.data['auraPoints'] as num?)?.toInt() ?? 0;
    final category   = item.data['category']   as String? ?? '';
    final isTop3     = index < 3;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
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
              ? [BoxShadow(color: _accent.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 3))]
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
                        VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Rank badge
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: isTop3 ? _accent.withValues(alpha: 0.90) : Colors.black54,
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
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w700, height: 1.3,
                        )),
                    const SizedBox(height: 5),
                    // Category + aura row
                    Row(
                      children: [
                        if (category.isNotEmpty) ...[
                          Text(category,
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          const Text(' · ', style: TextStyle(color: Colors.white24, fontSize: 11)),
                        ],
                        const Icon(Icons.diamond, color: _accent, size: 11),
                        const SizedBox(width: 3),
                        Text('$auraPoints',
                            style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Attempt count
                    if (item.attemptCount > 0)
                      Row(
                        children: [
                          const Icon(Icons.people_outline_rounded, color: Color(0xFFFF6B35), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '${_fmt(item.attemptCount)} attempts ${_windowLabel(tab)}',
                            style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Take button
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChallengeDetail(
                    title: title,
                    instructions: instructions,
                    videoUrl: videoUrl,
                    challengeId: item.challengeId,
                  ),
                )),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Take',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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
          Icon(Icons.local_fire_department_outlined, color: Colors.white24, size: 52),
          SizedBox(height: 16),
          Text('Nothing trending yet',
              style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Check back soon — the leaderboard heats up fast.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _rankLabel(int i) {
    switch (i) {
      case 0: return '🥇';
      case 1: return '🥈';
      case 2: return '🥉';
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

  const _TrendingItem({
    required this.challengeId,
    required this.data,
    required this.attemptCount,
  });
}
