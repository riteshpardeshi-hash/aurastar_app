import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/creators_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../challenges/screens/challenge_detail.dart';
import 'creator_profile_screen.dart';

class CreatorVideosScreen extends StatefulWidget {
  const CreatorVideosScreen({super.key});

  @override
  State<CreatorVideosScreen> createState() => _CreatorVideosScreenState();
}

class _CreatorVideosScreenState extends State<CreatorVideosScreen> {
  static const _bg     = Color(0xFF0D0D1A);
  static const _card   = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  static const _allCategories = ['All', 'Dance', 'Fitness', 'Fashion', 'Sports', 'Comedy', 'Skill'];
  int _activeCat = 0;

  String? _uid;
  List<Map<String, dynamic>>? _challenges;

  @override
  void initState() {
    super.initState();
    ApiClient().userId.then((id) {
      if (mounted) setState(() => _uid = id);
    });
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    setState(() => _challenges = null);
    final category = _activeCat > 0 ? _allCategories[_activeCat] : null;
    final raw = await ChallengesService()
        .fetchChallenges(sourceType: 'Brand', category: category, limit: 40);
    if (!mounted) return;
    setState(() => _challenges = raw.map(normaliseChallenge).toList());
  }

  void _selectCategory(int i) {
    setState(() => _activeCat = i);
    _loadChallenges();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Creator Videos'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white10),
        ),
      ),
      body: Column(
        children: [
          _buildFeaturedCreators(),
          _buildCategoryFilter(),
          Expanded(child: _buildChallengeList()),
        ],
      ),
    );
  }

  // ── Featured Creators strip ───────────────────────────────────────────────

  Widget _buildFeaturedCreators() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CreatorsService().fetchCreators(limit: 12),
      builder: (context, snap) {
        final creators = (snap.data ?? []).map(normaliseCreator).toList();
        if (creators.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text('Featured Creators',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: creators.length,
                itemBuilder: (_, i) => _creatorAvatar(creators[i]),
              ),
            ),
            const SizedBox(height: 4),
            Container(height: 1, color: Colors.white10),
          ],
        );
      },
    );
  }

  Widget _creatorAvatar(Map<String, dynamic> creator) {
    final id         = creator['id'] as String;
    final pageName   = creator['displayName'] as String;
    final followers  = creator['auraPoints'] as int; // no follower count on CreatorSummary
    final imgUrl     = creator['avatar'] as String;
    final isVerified = creator['isVerified'] as bool;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CreatorProfileScreen(creatorId: id),
      )),
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: _accent.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: imgUrl.isNotEmpty
                      ? ClipOval(child: Image.network(imgUrl, fit: BoxFit.cover))
                      : Center(
                          child: Text(
                            pageName.isNotEmpty ? pageName[0].toUpperCase() : 'C',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ),
                ),
                // Verified badge
                if (isVerified)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: _bg, width: 1.5),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              pageName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            if (followers > 0)
              Text(
                _fmt(followers),
                style: const TextStyle(color: AppColors.textFaint, fontSize: 9),
              ),
          ],
        ),
      ),
    );
  }

  // ── Category filter ───────────────────────────────────────────────────────

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _allCategories.length,
        itemBuilder: (_, i) {
          final active = i == _activeCat;
          return GestureDetector(
            onTap: () => _selectCategory(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? _accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? _accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Center(
                child: Text(
                  _allCategories[i],
                  style: TextStyle(
                    color: active ? const Color(0xFFD4A8FF) : AppColors.textFaint,
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

  // ── Challenge list ─────────────────────────────────────────────────────────
  // Non-system creatorId challenges are brand accounts in the current backend
  // model (see /brands/*), filtered here via GET /challenges?sourceType=Brand.

  Widget _buildChallengeList() {
    final challenges = _challenges;
    if (challenges == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (challenges.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadChallenges,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: challenges.length,
        itemBuilder: (_, i) => _buildChallengeCard(challenges[i]),
      ),
    );
  }

  // ── Challenge card ────────────────────────────────────────────────────────

  Widget _buildChallengeCard(Map<String, dynamic> data) {
    final id           = data['id']            as String;
    final title        = data['title']         as String? ?? '';
    final videoUrl     = data['videoUrl']       as String? ?? '';
    final instructions = data['instructions']  as String? ?? '';
    final auraPoints   = (data['starsCount']   as num?)?.toInt() ?? 0;
    final category     = data['category']      as String? ?? '';
    final creatorId    = data['creatorId']      as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          GestureDetector(
            onTap: () => _openDetail(id, title, instructions, videoUrl),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 180,
                width: double.infinity,
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
                            stops: const [0.4, 1.0],
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                          ),
                        ),
                      ),
                    ),
                    // Play icon
                    Center(
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                    // Category badge
                    if (category.isNotEmpty)
                      Positioned(
                        top: 10, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(category,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    // Aura badge
                    Positioned(
                      top: 10, right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.diamond, color: Colors.white, size: 10),
                            const SizedBox(width: 3),
                            Text('$auraPoints',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Creator info + CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Creator info
                Expanded(
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
                      const SizedBox(height: 6),
                      if (creatorId.isNotEmpty)
                        _CreatorNameChip(creatorId: creatorId),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // CTA column
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _openDetail(id, title, instructions, videoUrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Take',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (_uid != null && creatorId.isNotEmpty && creatorId != _uid) ...[
                      const SizedBox(height: 6),
                      FollowButton(targetUserId: creatorId),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(String id, String title, String instructions, String videoUrl) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChallengeDetail(
        title: title,
        instructions: instructions,
        videoUrl: videoUrl,
        challengeId: id,
      ),
    ));
  }

  Widget _buildEmpty() {
    final cat = _activeCat > 0 ? _allCategories[_activeCat] : '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 52),
            const SizedBox(height: 16),
            Text(
              cat.isNotEmpty ? 'No $cat creator challenges yet' : 'No creator challenges yet',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('Check back soon — creators are always adding new challenges.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}

// ── Creator name chip (async fetch) ───────────────────────────────────────────

class _CreatorNameChip extends StatelessWidget {
  final String creatorId;
  const _CreatorNameChip({required this.creatorId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: CreatorsService().fetchCreator(creatorId),
      builder: (context, snap) {
        final data     = snap.data != null ? normaliseCreator(snap.data!) : <String, dynamic>{};
        final pageName = data['displayName'] as String? ?? 'Creator';
        final imgUrl   = data['avatar'] as String? ?? '';

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreatorProfileScreen(creatorId: creatorId),
          )),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: imgUrl.isNotEmpty
                    ? ClipOval(child: Image.network(imgUrl, fit: BoxFit.cover))
                    : Center(
                        child: Text(
                          pageName.isNotEmpty ? pageName[0].toUpperCase() : 'C',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(pageName,
                  style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.verified_rounded, color: Color(0xFF7B2CBF), size: 12),
            ],
          ),
        );
      },
    );
  }
}
