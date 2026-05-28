import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'review_screen.dart';
import 'creator_review_screen.dart';
import 'challenge_submissions_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Panel"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Pending"),
              Tab(text: "By Challenge"),
              Tab(text: "Brand Requests"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SubmissionTab(),
            ChallengeSubmissionsTab(),
            CreatorRequestTab(),
          ],
        ),
      ),
    );
  }
}

class SubmissionTab extends StatelessWidget {
  const SubmissionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final submissions = snapshot.data!.docs;

        if (submissions.isEmpty) {
          return const Center(child: Text("No submissions"));
        }

        return ListView.builder(
          itemCount: submissions.length,
          itemBuilder: (context, index) {
            final s = submissions[index];

            return Card(
              child: ListTile(
                title: Text(s['challengeTitle'] ?? ''),
                subtitle: Text("User: ${s['userId']}"),
                trailing: ElevatedButton(
                  child: const Text("Review"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewScreen(submission: s),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CreatorRequestTab extends StatelessWidget {
  const CreatorRequestTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('creator_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return const Center(child: Text("No brand requests"));
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final r = requests[index];

            return Card(
              child: ListTile(
                title: Text(r['title'] ?? ''),
                subtitle: Text("Creator: ${r['creatorId']}"),
                trailing: ElevatedButton(
                  child: const Text("Review"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreatorReviewScreen(request: r),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
