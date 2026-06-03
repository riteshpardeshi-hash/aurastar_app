import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../challenges/screens/challenge_detail.dart';

class CreatorProfileScreen extends StatelessWidget {
  final String creatorId;

  const CreatorProfileScreen({super.key, required this.creatorId});

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(creatorId);

    final challengesRef = FirebaseFirestore.instance
        .collection('challenges')
        .where('creatorId', isEqualTo: creatorId)
        .where('status', isEqualTo: 'approved');

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: StreamBuilder<DocumentSnapshot>(
        stream: userRef.snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = userData['name'] ?? 'Creator';
          final username = userData['username'] ?? 'creator';
          final pageName = userData['pageName'] ?? '';
          final bio = userData['bio'] ?? '';
          final profileImageUrl = userData['profileImageUrl'] ?? '';
          final totalRewards = userData['totalRewards'] ?? 0;
          final followerCount =
              (userData['followerCount'] as num?)?.toInt() ?? 0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 290,
                pinned: true,
                backgroundColor: Colors.deepPurple,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            CircleAvatar(
                              radius: 42,
                              backgroundColor: Colors.white24,
                              backgroundImage: profileImageUrl.isNotEmpty
                                  ? NetworkImage(profileImageUrl)
                                  : null,
                              child: profileImageUrl.isEmpty
                                  ? const Icon(Icons.person, size: 42, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              pageName.isNotEmpty ? pageName : name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "@$username",
                              style: const TextStyle(color: Colors.white70, fontSize: 15),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bio.isNotEmpty ? bio : "This creator has not added a bio yet.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 14),
                            FollowButton(targetUserId: creatorId),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: challengesRef.snapshots(),
                    builder: (context, challengeSnapshot) {
                      if (!challengeSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final challenges = challengeSnapshot.data!.docs;
                      final challengeCount = challenges.length;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  title: "Followers",
                                  value: "$followerCount",
                                  icon: Icons.people_rounded,
                                  color: Colors.purple,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  title: "Challenges",
                                  value: "$challengeCount",
                                  icon: Icons.flash_on,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  title: "Aura Points",
                                  value: "$totalRewards",
                                  icon: Icons.auto_awesome,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Live Challenges",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (challenges.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                "No live challenges yet.",
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            GridView.builder(
                              itemCount: challenges.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.88,
                              ),
                              itemBuilder: (context, index) {
                                final c = challenges[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChallengeDetail(
                                          title: c['title'] ?? "",
                                          instructions: c['instructions'] ?? "No instructions",
                                          videoUrl: c['videoUrl'] ?? "",
                                          challengeId: c.id,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF2E86DE), Color(0xFF54A0FF)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.videocam_rounded, color: Colors.white, size: 28),
                                        const Spacer(),
                                        Text(
                                          c['title'] ?? 'No Title',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          c['description'] ?? '',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
