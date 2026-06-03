import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../challenges/screens/challenge_detail.dart';
import '../../explore/screens/creator_profile_screen.dart';
import '../../explore/screens/participant_profile_screen.dart';
import '../../video/screens/public_video_screen.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleStar(
      String submissionId, List starredBy, String ownerId) async {
    if (_uid == null) return;
    final isStarred = starredBy.contains(_uid);
    final submissionRef =
        FirebaseFirestore.instance.collection('submissions').doc(submissionId);
    final delta = isStarred ? -1 : 1;

    await submissionRef.update({
      'starredBy': isStarred
          ? FieldValue.arrayRemove([_uid])
          : FieldValue.arrayUnion([_uid]),
      'starsCount': FieldValue.increment(delta),
    });

    // Keep owner's starsReceived in sync (skip own videos)
    if (ownerId.isNotEmpty && ownerId != _uid) {
      FirebaseFirestore.instance.collection('users').doc(ownerId).update({
        'starsReceived': FieldValue.increment(delta),
      });
    }
  }

  void _showReportSheet(BuildContext context, String submissionId) {
    const reasons = [
      'Bullying / harassment',
      'Unsafe act',
      'Nudity / sexual content',
      'Spam / fake account',
      'Other',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Report Video',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Why are you reporting this?',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            ...reasons.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white24, size: 18),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('reports')
                        .add({
                      'submissionId': submissionId,
                      'reportedBy': _uid,
                      'reason': r,
                      'createdAt': Timestamp.now(),
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Report submitted. Thank you.')),
                      );
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Image.asset('assets/images/Aura Arena Mono.png', height: 30),
        ),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'For You'),
            Tab(text: 'Following'),
            Tab(text: 'Trending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildFeed('createdAt'),
          _buildFollowingFeed(),
          _buildFeed('starsCount'),
        ],
      ),
    );
  }

  Widget _buildFollowingFeed() {
    if (_uid == null) {
      return const Center(
        child: Text('Log in to see your following feed',
            style: TextStyle(color: Colors.white38)),
      );
    }

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('follows')
          .where('followerUserId', isEqualTo: _uid)
          .limit(30)
          .get(),
      builder: (context, followSnap) {
        if (followSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _accent));
        }

        final followedIds = (followSnap.data?.docs ?? [])
            .map((d) =>
                (d.data() as Map<String, dynamic>)['followedUserId']
                    as String? ??
                '')
            .where((id) => id.isNotEmpty)
            .toList();

        if (followedIds.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded,
                      color: Colors.white24, size: 52),
                  SizedBox(height: 14),
                  Text(
                    "You're not following anyone yet",
                    style:
                        TextStyle(color: Colors.white38, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Follow players and creators to see their videos here',
                    style:
                        TextStyle(color: Colors.white24, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('submissions')
              .where('userId', whereIn: followedIds)
              .where('isPublic', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .limit(30)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _accent));
            }

            final docs = snap.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library_outlined,
                        color: Colors.white24, size: 52),
                    SizedBox(height: 14),
                    Text(
                      'No videos yet from people you follow',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc = docs[i];
                return _buildCard(
                    doc.id, doc.data() as Map<String, dynamic>);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFeed(String orderBy) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('isPublic', isEqualTo: true)
          .orderBy(orderBy, descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline_rounded, color: Colors.white24, size: 52),
                const SizedBox(height: 14),
                const Text(
                  'No posts yet',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Be the first to share a challenge!',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            return _buildCard(doc.id, doc.data() as Map<String, dynamic>);
          },
        );
      },
    );
  }

  Widget _buildCard(String submissionId, Map<String, dynamic> data) {
    final username = data['username'] as String? ?? 'User';
    final userId = data['userId'] as String? ?? '';
    final challengeTitle = data['challengeTitle'] as String? ?? 'Challenge';
    final challengeId = data['challengeId'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final aiScore = (data['aiScore'] as num?)?.toInt();
    final starsCount = (data['starsCount'] as num?)?.toInt() ?? 0;
    final starredBy = (data['starredBy'] as List?) ?? [];
    final isStarred = starredBy.contains(_uid);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0D0D1F),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Tappable avatar → participant profile
                GestureDetector(
                  onTap: userId.isNotEmpty
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ParticipantProfileScreen(userId: userId),
                            ),
                          )
                      : null,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: _accent.withValues(alpha: 0.3),
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tappable username → participant profile
                      GestureDetector(
                        onTap: userId.isNotEmpty
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ParticipantProfileScreen(
                                        userId: userId),
                                  ),
                                )
                            : null,
                        child: Text(username,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                      // Tappable challenge title → challenge detail
                      GestureDetector(
                        onTap: challengeId.isNotEmpty
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChallengeDetail(
                                      title: challengeTitle,
                                      instructions: '',
                                      videoUrl: videoUrl,
                                      challengeId: challengeId,
                                    ),
                                  ),
                                )
                            : null,
                        child: Text(
                          challengeTitle,
                          style: const TextStyle(
                              color: Color(0xFFBB6BD9), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (challengeId.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _SourceChip(challengeId: challengeId),
                      ],
                    ],
                  ),
                ),
                if (aiScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '$aiScore',
                      style: const TextStyle(
                        color: Color(0xFFD4A8FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showReportSheet(context, submissionId),
                  child: const Icon(Icons.more_vert_rounded,
                      color: Colors.white38, size: 20),
                ),
              ],
            ),
          ),

          // ── Video placeholder (tap to open full-screen player) ───────────
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicVideoScreen(
                  submissionId: submissionId,
                  videoUrl: videoUrl,
                  username: username,
                  userId: userId,
                  challengeTitle: challengeTitle,
                  challengeId: challengeId,
                  challengeVideoUrl: videoUrl,
                  initialStars: starsCount,
                  initiallyStarred: isStarred,
                  auraScore: aiScore,
                ),
              ),
            ),
            child: Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accent.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Icon(Icons.play_circle_outline_rounded,
                    color: Colors.white60, size: 64),
              ),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                // Star button
                GestureDetector(
                  onTap: () => _toggleStar(submissionId, starredBy, userId),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                          key: ValueKey(isStarred),
                          color: isStarred ? const Color(0xFFFFD700) : Colors.white54,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$starsCount',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Take Challenge button
                if (challengeId.isNotEmpty)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChallengeDetail(
                          title: challengeTitle,
                          instructions: '',
                          videoUrl: videoUrl,
                          challengeId: challengeId,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Take Challenge',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Source attribution chip ────────────────────────────────────────────────────

class _SourceInfo {
  final String label;
  final String? creatorId; // null = official AURA ARENA challenge
  const _SourceInfo(this.label, this.creatorId);
}

class _SourceChip extends StatelessWidget {
  static final Map<String, Future<_SourceInfo>> _cache = {};

  final String challengeId;
  const _SourceChip({required this.challengeId});

  static Future<_SourceInfo> _resolve(String id) {
    return _cache.putIfAbsent(id, () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('challenges')
            .doc(id)
            .get();
        if (!doc.exists) return const _SourceInfo('AURA ARENA', null);

        final creatorId =
            (doc.data()!['creatorId'] as String? ?? '').trim();

        if (creatorId.isEmpty || creatorId == 'system') {
          return const _SourceInfo('AURA ARENA', null);
        }

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(creatorId)
            .get();
        final username =
            ((userDoc.data() ?? {})['username'] as String? ?? '').trim();
        return _SourceInfo(
          username.isNotEmpty ? '@$username' : '@creator',
          creatorId,
        );
      } catch (_) {
        return const _SourceInfo('AURA ARENA', null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SourceInfo>(
      future: _resolve(challengeId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final info = snap.data!;
        final isOfficial = info.creatorId == null;
        final chipColor =
            isOfficial ? const Color(0xFF7B2CBF) : const Color(0xFF4B6EF6);
        final textColor =
            isOfficial ? const Color(0xFFD4A8FF) : const Color(0xFF93B4FF);

        return GestureDetector(
          onTap: info.creatorId != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreatorProfileScreen(creatorId: info.creatorId!),
                    ),
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chipColor.withValues(alpha: 0.40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOfficial
                      ? Icons.auto_awesome_rounded
                      : Icons.person_rounded,
                  color: textColor,
                  size: 9,
                ),
                const SizedBox(width: 3),
                Text(
                  info.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
