import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/aura_tier.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../video/screens/video_feed_screen.dart';

class ParticipantProfileScreen extends StatelessWidget {
  final String userId;
  const ParticipantProfileScreen({super.key, required this.userId});

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);
  static const int _xpPerLevel = 1300;

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwn = currentUid == userId;

    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              backgroundColor: _bg,
              body: Center(
                  child: CircularProgressIndicator(color: _accent)),
            );
          }

          final data =
              snap.data!.data() as Map<String, dynamic>? ?? {};
          final name = data['name'] as String? ?? 'User';
          final username = data['username'] as String? ?? '';
          final bio = data['bio'] as String? ?? '';
          final photoUrl =
              data['profileImageUrl'] as String? ?? '';
          final totalRewards =
              (data['totalRewards'] as num?)?.toInt() ?? 0;
          final followerCount =
              (data['followerCount'] as num?)?.toInt() ?? 0;
          final followingCount =
              (data['followingCount'] as num?)?.toInt() ?? 0;
          final level = _level(totalRewards);
          final tier = auraTierForLevel(level);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: _bg,
                foregroundColor: Colors.white,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tier.color.withValues(alpha: 0.22),
                          _bg,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 44),

                          // Avatar
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: tier.color, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      tier.color.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: photoUrl.isNotEmpty
                                  ? Image.network(photoUrl,
                                      fit: BoxFit.cover)
                                  : Container(
                                      color: _accent.withValues(alpha: 0.3),
                                      child: Center(
                                        child: Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : 'U',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 34,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@$username',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 14),
                          ),
                          const SizedBox(height: 8),

                          // Level badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  tier.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: tier.color
                                      .withValues(alpha: 0.55)),
                            ),
                            child: Text(
                              'Level $level · ${tier.name}',
                              style: TextStyle(
                                color: tier.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Stats row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _stat(_fmt(followerCount), 'Followers'),
                              _divider(),
                              _stat(_fmt(followingCount), 'Following'),
                              _divider(),
                              _stat(_fmt(totalRewards), 'Auras'),
                            ],
                          ),

                          if (!isOwn) ...[
                            const SizedBox(height: 14),
                            FollowButton(targetUserId: userId),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bio
              if (bio.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      bio,
                      style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ),
                ),

              // Videos header
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text(
                    'Videos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              _PublicVideosSliver(userId: userId),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
        ],
      );

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: Colors.white12,
        margin: const EdgeInsets.symmetric(horizontal: 16),
      );

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Public videos grid ────────────────────────────────────────────────────────

class _PublicVideosSliver extends StatelessWidget {
  final String userId;
  const _PublicVideosSliver({required this.userId});

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('userId', isEqualTo: userId)
          .where('isPublic', isEqualTo: true)
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(18)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No public videos yet',
                  style: TextStyle(color: Colors.white24, fontSize: 14),
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          sliver: SliverGrid(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 0.7,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final data =
                    docs[i].data() as Map<String, dynamic>;
                final videoUrl =
                    data['videoUrl'] as String? ?? '';
                final aiScore =
                    (data['aiScore'] as num?)?.toInt();

                return GestureDetector(
                  onTap: () {
                    final submissions = docs
                        .map((d) => {
                              'id': d.id,
                              'data': d.data()
                                  as Map<String, dynamic>,
                            })
                        .toList();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoFeedScreen(
                          submissions: submissions,
                          initialIndex: i,
                        ),
                      ),
                    );
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoThumbnailWidget(
                          videoUrl: videoUrl,
                          fit: BoxFit.cover),
                      if (aiScore != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.90),
                              borderRadius:
                                  BorderRadius.circular(5),
                            ),
                            child: Text(
                              '$aiScore',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
              childCount: docs.length,
            ),
          ),
        );
      },
    );
  }
}
