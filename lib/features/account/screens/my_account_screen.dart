import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/aura_tier.dart';
import '../../auth/screens/login_screen.dart';
import 'user_video_detail_screen.dart';

class MyAccountScreen extends StatelessWidget {
  const MyAccountScreen({super.key});

  static const int _xpPerLevel = 1300;
  static const _accent = Color(0xFF7B2CBF);

  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;
  int _xpInLevel(int pts) => pts % _xpPerLevel;
  double _progress(int pts) => (pts % _xpPerLevel) / _xpPerLevel;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _buildLevelStar(int level) {
    final tier = auraTierForLevel(level);
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/Aura star level container.png',
            width: 100,
            height: 100,
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Level', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Text(
                '$level',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              Text(
                tier.name,
                style: TextStyle(
                  color: tier.color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuraPointsCard(int points) {
    final level = _level(points);
    final progress = _progress(points);
    final xpToNext = _xpPerLevel - _xpInLevel(points);

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/level analysis banner.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your Aura Points',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _fmt(points),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildLevelStar(level),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$xpToNext XP to Next Level',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 5,
                            width: constraints.maxWidth * progress,
                            child: Image.asset('assets/images/bar.png', fit: BoxFit.fill),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("My Account"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to log out?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Logout"),
                      ),
                    ],
                  );
                },
              );

              if (shouldLogout != true) return;

              await FirebaseAuth.instance.signOut();

              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("User data error: ${userSnapshot.error}"),
              ),
            );
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text("User profile not found."));
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = userData['name'] ?? 'User';
          final username = userData['username'] ?? '';
          final gender = (userData['gender'] as String? ?? '').trim();
          final totalRewards = userData['totalRewards'] ?? 0;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('submissions')
                .where('userId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Submission error: ${submissionSnapshot.error}",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (submissionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!submissionSnapshot.hasData) {
                return const Center(child: Text("No submission data found."));
              }

              final submissions = submissionSnapshot.data!.docs.toList();

              submissions.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aCreatedAt = aData['createdAt'];
                final bCreatedAt = bData['createdAt'];
                if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
                  return bCreatedAt.compareTo(aCreatedAt);
                }
                return 0;
              });

              final totalSubmissions = submissions.length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3A1C71), Color(0xFFD76D77)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "@$username",
                            style: const TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                          if (gender.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, color: Colors.white54, size: 15),
                                const SizedBox(width: 5),
                                Text(
                                  gender,
                                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildAuraPointsCard(totalRewards),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
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
                          const Icon(Icons.video_collection, size: 32, color: Colors.deepPurple),
                          const SizedBox(height: 10),
                          Text(
                            "$totalSubmissions",
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text("Total Videos Submitted", style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "My Videos",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (submissions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "You have not submitted any videos yet.",
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Column(
                        children: submissions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final doc = entry.value;
                          final data = doc.data() as Map<String, dynamic>;

                          final auraPoints = data['auraPoints'] ?? 0;
                          final videoUrl = data['videoUrl'] ?? '';
                          final status = data['status'] ?? 'pending';
                          final aiScore = data['aiScore'];
                          final aiReason = data['aiReason'] ?? '';
                          final reviewedByAI = data['reviewedByAI'] == true;
                          final challengeTitle = data['challengeTitle'] ?? '';

                          Color statusColor;
                          String statusLabel;
                          IconData statusIcon;
                          if (status == 'approved') {
                            statusColor = Colors.green;
                            statusLabel = 'Approved';
                            statusIcon = Icons.check_circle;
                          } else if (status == 'rejected') {
                            statusColor = Colors.red;
                            statusLabel = 'Rejected';
                            statusIcon = Icons.cancel;
                          } else if (status == 'ai_error') {
                            statusColor = Colors.orange;
                            statusLabel = 'Manual Review';
                            statusIcon = Icons.pending;
                          } else {
                            statusColor = const Color(0xFF7B2CBF);
                            statusLabel = 'AI Reviewing...';
                            statusIcon = Icons.auto_awesome;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      challengeTitle.isNotEmpty ? challengeTitle : "Video ${index + 1}",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          status == 'pending'
                                              ? SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: statusColor,
                                                  ),
                                                )
                                              : Icon(statusIcon, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            statusLabel,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (reviewedByAI && aiScore != null) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, size: 16, color: Color(0xFF7B2CBF)),
                                      const SizedBox(width: 4),
                                      Text(
                                        "AI Score: $aiScore / 100",
                                        style: const TextStyle(
                                          color: Color(0xFF7B2CBF),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (status == 'approved') ...[
                                        const SizedBox(width: 12),
                                        Text(
                                          "+$auraPoints pts",
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (aiReason.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      aiReason,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ] else if (status == 'approved') ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    "Aura Points: $auraPoints",
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                if (videoUrl.toString().isNotEmpty)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UserVideoDetailScreen(
                                              videoNumber: index + 1,
                                              auraPoints: auraPoints,
                                              videoUrl: videoUrl,
                                              status: status,
                                              aiScore: aiScore,
                                              aiReason: aiReason,
                                              reviewedByAI: reviewedByAI,
                                              submissionId: doc.id,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text("View Video"),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
