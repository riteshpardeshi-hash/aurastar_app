import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'brand_participants_screen.dart';

class CreatorAdminScreen extends StatelessWidget {
  const CreatorAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(title: const Text("Brand Admin Panel")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .where('creatorId', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, challengeSnapshot) {
          if (challengeSnapshot.hasError) {
            return Center(child: Text("Error: ${challengeSnapshot.error}"));
          }

          if (challengeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = challengeSnapshot.data?.docs ?? [];
          final challengeIds = challenges.map((doc) => doc.id).toList();

          if (challengeIds.isEmpty) {
            return const Center(child: Text("No approved brand challenges yet."));
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('submissions')
                .where('challengeId', whereIn: challengeIds.take(30).toList())
                .snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(child: Text("Error: ${submissionSnapshot.error}"));
              }

              if (submissionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final creatorSubmissions = submissionSnapshot.data?.docs ?? [];

              final totalChallenges = challenges.length;
              final totalSubmissions = creatorSubmissions.length;

              final uniqueUserIds = creatorSubmissions
                  .map((doc) =>
                      (doc.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .toList();

              final uniqueUsers = uniqueUserIds.length;
              final averageVideosPerUser =
                  uniqueUsers == 0 ? 0.0 : totalSubmissions / uniqueUsers;
              const costPerUser = "₹0";

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Campaign Overview",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Total Challenges",
                            value: "$totalChallenges",
                            icon: Icons.flash_on,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: uniqueUserIds.isEmpty
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BrandParticipantsScreen(
                                          userIds: uniqueUserIds,
                                        ),
                                      ),
                                    );
                                  },
                            child: _reportCard(
                              title: "Unique Users",
                              value: "$uniqueUsers",
                              icon: Icons.people,
                              color: Colors.orange,
                              subtitle: "Tap to view",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Total Submissions",
                            value: "$totalSubmissions",
                            icon: Icons.video_collection,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _reportCard(
                            title: "Average Videos/User",
                            value: averageVideosPerUser.toStringAsFixed(1),
                            icon: Icons.analytics,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Cost Per User",
                            value: costPerUser,
                            icon: Icons.currency_rupee,
                            color: Colors.pink,
                            subtitle: "Frontend only",
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Challenge-wise Report",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: challenges.map((challengeDoc) {
                        final challengeData = challengeDoc.data() as Map<String, dynamic>;
                        final title = challengeData['title'] ?? 'No Title';

                        final challengeSubmissions = creatorSubmissions.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['challengeId'] == challengeDoc.id;
                        }).toList();

                        final totalChallengeSubmissions = challengeSubmissions.length;
                        final challengeUserIds = challengeSubmissions
                            .map((doc) =>
                                (doc.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
                            .where((id) => id.isNotEmpty)
                            .toSet()
                            .toList();

                        final challengeUniqueUsers = challengeUserIds.length;
                        final avgVideosPerUser = challengeUniqueUsers == 0
                            ? 0.0
                            : totalChallengeSubmissions / challengeUniqueUsers;

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Text("Total Submissions: $totalChallengeSubmissions"),
                              Text("Unique Users: $challengeUniqueUsers"),
                              Text("Average Videos/User: ${avgVideosPerUser.toStringAsFixed(1)}"),
                              const Text("Cost Per User: ₹0"),
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

  Widget _reportCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
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
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.deepPurple,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
