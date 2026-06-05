import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'challenge_detail.dart';

// Category metadata — single source of truth used by both this screen and dashboard
const categoryMeta = <String, ({IconData icon, Color color})>{
  'Dance':   (icon: Icons.music_note_rounded,        color: Color(0xFF4B6EF6)),
  'Fitness': (icon: Icons.fitness_center_rounded,    color: Color(0xFF22C55E)),
  'Fashion': (icon: Icons.checkroom_rounded,         color: Color(0xFFFF6B9D)),
  'Sports':  (icon: Icons.sports_basketball_rounded, color: Color(0xFFF97316)),
  'Comedy':  (icon: Icons.mood_rounded,              color: Color(0xFFEAB308)),
  'Skill':   (icon: Icons.psychology_rounded,        color: Color(0xFF06B6D4)),
};

class CategoryChallengesScreen extends StatefulWidget {
  final String category;

  const CategoryChallengesScreen({super.key, required this.category});

  @override
  State<CategoryChallengesScreen> createState() => _CategoryChallengesScreenState();
}

class _CategoryChallengesScreenState extends State<CategoryChallengesScreen> {
  static const _bg     = Color(0xFF0D0D1A);
  static const _card   = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  static const _filters = ['Trending', 'New', 'Easy', 'High Aura'];
  int _activeFilter = 0;

  List<QueryDocumentSnapshot> _allDocs = [];
  bool _loading = true;
  int _totalAttempts = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('challenges')
          .where('category', isEqualTo: widget.category)
          .where('status',   isEqualTo: 'approved')
          .limit(40)
          .get();

      // Attempt count — best-effort aggregate
      int attempts = 0;
      try {
        final countSnap = await FirebaseFirestore.instance
            .collection('submissions')
            .where('status', isEqualTo: 'approved')
            .where('challengeId', whereIn: snap.docs.isEmpty
                ? ['__none__']
                : snap.docs.map((d) => d.id).take(30).toList())
            .count()
            .get();
        attempts = countSnap.count ?? 0;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _allDocs      = snap.docs;
        _totalAttempts = attempts;
        _loading      = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filtered + sorted docs ────────────────────────────────────────────────

  List<QueryDocumentSnapshot> get _filtered {
    var docs = List<QueryDocumentSnapshot>.from(_allDocs);

    switch (_activeFilter) {
      case 0: // Trending — sort by starsCount desc
        docs.sort((a, b) {
          final sa = (a.data() as Map)['starsCount'] as num? ?? 0;
          final sb = (b.data() as Map)['starsCount'] as num? ?? 0;
          return sb.compareTo(sa);
        });
      case 1: // New — sort by createdAt desc
        docs.sort((a, b) {
          final ta = (a.data() as Map)['createdAt'];
          final tb = (b.data() as Map)['createdAt'];
          if (ta == null || tb == null) return 0;
          return (tb as Timestamp).compareTo(ta as Timestamp);
        });
      case 2: // Easy — filter then sort by auraPoints
        docs = docs.where((d) {
          final diff = ((d.data() as Map)['difficulty'] as String? ?? '').toLowerCase();
          return diff == 'easy';
        }).toList();
        docs.sort((a, b) {
          final pa = (a.data() as Map)['auraPoints'] as num? ?? 0;
          final pb = (b.data() as Map)['auraPoints'] as num? ?? 0;
          return pb.compareTo(pa);
        });
      case 3: // High Aura — sort by auraPoints desc
        docs.sort((a, b) {
          final pa = (a.data() as Map)['auraPoints'] as num? ?? 0;
          final pb = (b.data() as Map)['auraPoints'] as num? ?? 0;
          return pb.compareTo(pa);
        });
    }

    return docs;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final meta   = categoryMeta[widget.category];
    final color  = meta?.color  ?? _accent;
    final icon   = meta?.icon   ?? Icons.category_outlined;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(color, icon),
          _buildFilterRow(color),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _filtered.isEmpty
                    ? _buildEmpty()
                    : _buildGrid(),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 14),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.category,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (_totalAttempts > 0)
                  Text(
                    '${_fmt(_totalAttempts)} attempts',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterRow(Color color) {
    return Container(
      height: 48,
      color: _bg,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _filters.length,
        itemBuilder: (_, i) {
          final active = i == _activeFilter;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? color.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Center(
                child: Text(
                  _filters[i],
                  style: TextStyle(
                    color: active ? color : Colors.white38,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Challenge grid ────────────────────────────────────────────────────────

  Widget _buildGrid() {
    final docs = _filtered;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildCard(docs[i]),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc) {
    final data        = doc.data() as Map<String, dynamic>;
    final title       = data['title']        as String? ?? '';
    final videoUrl    = data['videoUrl']      as String? ?? '';
    final instructions = data['instructions'] as String? ?? '';
    final auraPoints  = (data['auraPoints']  as num?)?.toInt() ?? 0;
    final difficulty  = data['difficulty']   as String? ?? '';
    final isSystem    = (data['creatorId']   as String? ?? '') == 'system';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChallengeDetail(
          title: title,
          instructions: instructions,
          videoUrl: videoUrl,
          challengeId: doc.id,
        ),
      )),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                    // Gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                          ),
                        ),
                      ),
                    ),
                    // Source badge top-left
                    Positioned(
                      top: 7, left: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isSystem ? _accent : const Color(0xFF4B6EF6)).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSystem ? 'Original' : 'Brand',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    // Difficulty badge top-right
                    if (difficulty.isNotEmpty)
                      Positioned(
                        top: 7, right: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _difficultyColor(difficulty).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            difficulty,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Info + CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.diamond, color: _accent, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '$auraPoints',
                        style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Try', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
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
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    final label = _activeFilter == 2 ? 'No Easy challenges yet' : 'No ${widget.category} challenges yet';
    final sub   = _activeFilter == 2
        ? 'Try a different filter to see more.'
        : 'Check back soon — more are being added!';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.white24, size: 52),
            const SizedBox(height: 16),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':   return Colors.green;
      case 'medium': return Colors.orange;
      case 'hard':   return Colors.deepOrange;
      case 'pro':    return Colors.red;
      default:       return Colors.white54;
    }
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}
