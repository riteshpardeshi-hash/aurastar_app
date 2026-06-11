import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../video/widgets/video_player_widget.dart';

class CreatorReviewScreen extends StatefulWidget {
  final QueryDocumentSnapshot request;

  const CreatorReviewScreen({super.key, required this.request});

  @override
  State<CreatorReviewScreen> createState() => _CreatorReviewScreenState();
}

class _CreatorReviewScreenState extends State<CreatorReviewScreen> {
  final reasonController = TextEditingController();

  Future<bool> _verifyAdmin() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    return doc.data()?['isAdmin'] == true;
  }

  Future<void> approve() async {
    if (!await _verifyAdmin()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unauthorized: admin access required")),
      );
      return;
    }

    final data = widget.request;
    final db = FirebaseFirestore.instance;

    // Atomic: create challenge + mark request approved together
    final batch = db.batch();
    final challengeRef = db.collection('challenges').doc();
    batch.set(challengeRef, {
      'title': data['title'],
      'description': data['description'],
      'instructions': data['instructions'],
      'videoUrl': data['videoUrl'],
      'creatorId': data['creatorId'],
      'status': 'approved',
      'createdAt': Timestamp.now(),
    });
    batch.update(db.collection('creator_requests').doc(data.id), {'status': 'approved'});
    await batch.commit();

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> reject() async {
    if (!await _verifyAdmin()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unauthorized: admin access required")),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('creator_requests')
        .doc(widget.request.id)
        .update({
      'status': 'rejected',
      'rejectionReason': reasonController.text,
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final videoUrl = widget.request['videoUrl'];

    return Scaffold(
      appBar: AppBar(title: const Text("Review Challenge")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 200, child: VideoPlayerWidget(videoUrl)),
            const SizedBox(height: 20),
            Text(widget.request['title'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(widget.request['description']),
            const SizedBox(height: 10),
            Text(widget.request['instructions']),
            const SizedBox(height: 20),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Rejection Reason (if rejecting)",
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: approve,
                    child: const Text("Approve"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: reject,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("Reject"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
