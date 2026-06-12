import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../features/search/search_screen.dart';
import '../../../features/leaderboard/leaderboard_screen.dart';
import '../../../features/account/screens/my_account_screen.dart';
import '../../../shared/widgets/aura_action_sheet.dart';
import 'challenge_detail.dart';

class AllGeneralChallengesScreen extends StatelessWidget {
  const AllGeneralChallengesScreen({super.key});

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Search bar ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        _buildSearchBar(context),
                      ],
                    ),
                  ),
                ),

                // ── Top Picks For You ────────────────────────────────────────
                SliverToBoxAdapter(
                    child: _TopPicksSection()),

                // ── Score More Aura (brand) ──────────────────────────────────
                SliverToBoxAdapter(
                    child: _ScoreMoreAuraSection()),

                // ── Featured brand card ──────────────────────────────────────
                SliverToBoxAdapter(
                    child: _FeaturedCard()),

                // ── All challenges grid ──────────────────────────────────────
                SliverToBoxAdapter(
                    child: _AllChallengesGrid()),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                color: Colors.white.withValues(alpha: 0.40), size: 20),
            const SizedBox(width: 10),
            Text(
              'Search challenges…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 15),
            ),
          ],
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
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                ),
                _navItem(
                  icon: Icons.flag_rounded,
                  label: 'Challenges',
                  active: true,
                  onTap: () {},
                ),
                const SizedBox(width: 64),
                _navItem(
                  icon: Icons.leaderboard_rounded,
                  label: 'Leaderboard',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LeaderboardScreen()),
                  ),
                ),
                _navItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MyAccountScreen()),
                  ),
                ),
              ],
            ),
            Positioned(
              top: -22,
              child: GestureDetector(
                onTap: () => showAuraActionSheet(context),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.55), width: 1.5),
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
                          _accent, BlendMode.srcIn),
                      child: Image.asset('assets/images/Aura Arena Mono.png',
                          fit: BoxFit.contain),
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
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: active ? _accent : Colors.white54, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: active ? _accent : Colors.white38, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ── Top Picks For You ──────────────────────────────────────────────────────────
class _TopPicksSection extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Top Picks For You',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const Text('>>',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      letterSpacing: 2)),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .where('creatorId', isEqualTo: 'system')
              .limit(6)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return const SizedBox(height: 100);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.75,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] as String? ?? '';
                  final videoUrl = data['videoUrl'] as String? ?? '';
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChallengeDetail(
                          title: title,
                          instructions:
                              data['instructions'] as String? ?? '',
                          videoUrl: videoUrl,
                          challengeId: doc.id,
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoThumbnailWidget(
                              videoUrl: videoUrl, fit: BoxFit.cover),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.5, 1.0],
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            right: 6,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Score More Aura ────────────────────────────────────────────────────────────
class _ScoreMoreAuraSection extends StatelessWidget {
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Score More Aura',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const Text('>>',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      letterSpacing: 2)),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('challenges')
              .where('creatorId', isNotEqualTo: 'system')
              .limit(3)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return const SizedBox(height: 8);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: List.generate(docs.length, (i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] as String? ?? '';
                  final videoUrl = data['videoUrl'] as String? ?? '';
                  final auraPoints =
                      (data['auraPoints'] as num?)?.toInt() ?? 150;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChallengeDetail(
                              title: title,
                              instructions:
                                  data['instructions'] as String? ?? '',
                              videoUrl: videoUrl,
                              challengeId: doc.id,
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 120,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                VideoThumbnailWidget(
                                    videoUrl: videoUrl, fit: BoxFit.cover),
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: [0.4, 1.0],
                                      colors: [
                                        Colors.transparent,
                                        Colors.black
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  left: 6,
                                  right: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.diamond,
                                              color: _accent, size: 11),
                                          const SizedBox(width: 3),
                                          Text(
                                            '$auraPoints',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Featured brand card ────────────────────────────────────────────────────────
class _FeaturedCard extends StatelessWidget {
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('creatorId', isNotEqualTo: 'system')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        // Fall back to system challenge if no brand challenges
        if (docs.isEmpty) {
          return _buildFallback(context);
        }
        final doc = docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final title = data['title'] as String? ?? 'Challenge';
        final instructions = data['instructions'] as String? ?? '';
        final videoUrl = data['videoUrl'] as String? ?? '';
        final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;

        return _buildCard(
            context, doc.id, title, instructions, videoUrl, auraPoints);
      },
    );
  }

  Widget _buildFallback(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('creatorId', isEqualTo: 'system')
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        final doc = docs.first;
        final data = doc.data() as Map<String, dynamic>;
        return _buildCard(
          context,
          doc.id,
          data['title'] as String? ?? '',
          data['instructions'] as String? ?? '',
          data['videoUrl'] as String? ?? '',
          (data['auraPoints'] as num?)?.toInt() ?? 150,
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, String challengeId, String title,
      String instructions, String videoUrl, int auraPoints) {
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
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0D0020),
          border: Border.all(color: _accent.withValues(alpha: 0.25)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail on the right half
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 200,
                child: VideoThumbnailWidget(
                    videoUrl: videoUrl, fit: BoxFit.cover),
              ),
              // Gradient from left (dark) to transparent
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.55, 0.85, 1.0],
                    colors: [
                      Color(0xFF0D0020),
                      Color(0xFF0D0020),
                      Color(0x880D0020),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Text content on the left
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                    if (instructions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        instructions,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.diamond,
                            color: _accent, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '$auraPoints',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
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
    );
  }
}

// ── All challenges 3-column grid ───────────────────────────────────────────────
class _AllChallengesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 0.72,
            ),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] as String? ?? '';
              final videoUrl = data['videoUrl'] as String? ?? '';
              final likes = (data['likes'] as List?)?.length ?? 0;
              final views = (data['views'] as num?)?.toInt() ?? likes;

              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChallengeDetail(
                      title: title,
                      instructions:
                          data['instructions'] as String? ?? '',
                      videoUrl: videoUrl,
                      challengeId: doc.id,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoThumbnailWidget(
                          videoUrl: videoUrl, fit: BoxFit.cover),
                      // Bottom gradient for views overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      // Views count
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Row(
                          children: [
                            const Icon(Icons.remove_red_eye_outlined,
                                color: Colors.white70, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              _fmt(views),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
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
      },
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
