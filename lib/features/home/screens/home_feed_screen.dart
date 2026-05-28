import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../challenges/screens/challenge_detail.dart';

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
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _toggleStar(String submissionId, List starredBy) async {
    if (_uid == null) return;
    final ref = FirebaseFirestore.instance.collection('submissions').doc(submissionId);
    final isStarred = starredBy.contains(_uid);
    if (isStarred) {
      await ref.update({
        'starredBy': FieldValue.arrayRemove([_uid]),
        'starsCount': FieldValue.increment(-1),
      });
    } else {
      await ref.update({
        'starredBy': FieldValue.arrayUnion([_uid]),
        'starsCount': FieldValue.increment(1),
      });
    }
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
          child: Image.asset('assets/images/aura star logo.png', height: 30),
        ),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [Tab(text: 'For You'), Tab(text: 'Trending')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildFeed('createdAt'),
          _buildFeed('starsCount'),
        ],
      ),
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
                CircleAvatar(
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text(
                        challengeTitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
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
              ],
            ),
          ),

          // ── Video placeholder ────────────────────────────────────────────
          Container(
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
                  color: Colors.white38, size: 60),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                // Star button
                GestureDetector(
                  onTap: () => _toggleStar(submissionId, starredBy),
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
