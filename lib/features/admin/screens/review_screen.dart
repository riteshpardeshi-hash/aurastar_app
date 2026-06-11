import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../video/widgets/video_player_widget.dart';

class ReviewScreen extends StatefulWidget {
  final QueryDocumentSnapshot submission;

  const ReviewScreen({super.key, required this.submission});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final pointsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final data = widget.submission.data() as Map<String, dynamic>;
    final existing = (data['netAurasAwarded'] as num?)?.toInt()
        ?? (data['auraPoints'] as num?)?.toInt()
        ?? 0;
    if (existing > 0) pointsController.text = existing.toString();
  }

  @override
  void dispose() {
    pointsController.dispose();
    super.dispose();
  }

  Future<void> approveSubmission() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final callerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (callerDoc.data()?['isAdmin'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized: admin access required")),
        );
        return;
      }

      final points = int.tryParse(pointsController.text) ?? 0;
      final data = widget.submission.data() as Map<String, dynamic>;
      final userId = data['userId'] as String? ?? '';
      final previousPoints = (data['netAurasAwarded'] as num?)?.toInt()
          ?? (data['auraPoints'] as num?)?.toInt()
          ?? 0;
      final wasApproved = data['status'] == 'approved';
      final delta = wasApproved ? (points - previousPoints) : points;

      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.update(db.collection('submissions').doc(widget.submission.id), {
        'status': 'approved',
        'auraPoints': points,
        'netAurasAwarded': points,
        'reviewed': true,
      });
      if (delta != 0 && userId.isNotEmpty) {
        batch.update(db.collection('users').doc(userId),
            {'totalRewards': FieldValue.increment(delta)});
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submission approved successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approve failed: $e")),
      );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(confirmLabel,
                    style: TextStyle(color: confirmColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> adminArchive() async {
    final ok = await _confirm(
      title: 'Archive Video',
      body: 'This video will be hidden from the platform. The user keeps their Aura Points.',
      confirmLabel: 'Archive',
      confirmColor: Colors.orange,
    );
    if (!ok || !mounted) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final callerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (callerDoc.data()?['isAdmin'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized: admin access required")),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('submissions')
          .doc(widget.submission.id)
          .update({'isArchived': true, 'isPublic': false});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video archived")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Archive failed: $e")));
    }
  }

  Future<void> adminDelete() async {
    final data = widget.submission.data() as Map<String, dynamic>;
    final auraPoints = (data['netAurasAwarded'] as num?)?.toInt()
        ?? (data['auraPoints'] as num?)?.toInt()
        ?? 0;
    final wasApproved = data['status'] == 'approved';
    final deduct = wasApproved ? auraPoints : 0;

    final ok = await _confirm(
      title: 'Delete Video',
      body: deduct > 0
          ? 'This will permanently remove the video and deduct $deduct Aura Points from the user.'
          : 'This will permanently remove the video from the platform.',
      confirmLabel: 'Delete',
      confirmColor: Colors.red,
    );
    if (!ok || !mounted) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final callerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (callerDoc.data()?['isAdmin'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized: admin access required")),
        );
        return;
      }

      final userId = data['userId'] as String? ?? '';
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.update(db.collection('submissions').doc(widget.submission.id), {
        'isDeleted': true,
        'isPublic': false,
        'isArchived': false,
        'isCountedForDailyAuras': false,
      });
      if (deduct > 0 && userId.isNotEmpty) {
        batch.update(db.collection('users').doc(userId),
            {'totalRewards': FieldValue.increment(-deduct)});
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video deleted from platform")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    }
  }

  Future<void> rejectSubmission() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final callerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (callerDoc.data()?['isAdmin'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized: admin access required")),
        );
        return;
      }

      final data = widget.submission.data() as Map<String, dynamic>;
      final wasApproved = data['status'] == 'approved';
      final previousPoints = (data['netAurasAwarded'] as num?)?.toInt()
          ?? (data['auraPoints'] as num?)?.toInt()
          ?? 0;
      final userId = data['userId'] as String? ?? '';

      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.update(db.collection('submissions').doc(widget.submission.id), {
        'status': 'rejected',
        'auraPoints': 0,
        'netAurasAwarded': 0,
        'reviewed': true,
      });
      if (wasApproved && previousPoints > 0 && userId.isNotEmpty) {
        batch.update(db.collection('users').doc(userId),
            {'totalRewards': FieldValue.increment(-previousPoints)});
      }
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submission rejected")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Reject failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.submission.data() as Map<String, dynamic>;
    final videoUrl = data['videoUrl'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final username = data['username'] as String? ?? data['userId'] as String? ?? 'Unknown';
    final challengeTitle = data['challengeTitle'] as String? ?? '';
    final aiReason = data['aiReason'] as String? ?? '';
    final auraPoints = (data['netAurasAwarded'] as num?)?.toInt()
        ?? (data['auraPoints'] as num?)?.toInt()
        ?? 0;
    final isPending = status == 'pending' || status == 'ai_error';

    return Scaffold(
      appBar: AppBar(title: const Text("Review Submission")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Submission info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(challengeTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text("by $username",
                          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 16),

            // Video player
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 220, child: VideoPlayerWidget(videoUrl)),
            ),
            const SizedBox(height: 16),

            // Aura points display (for already-processed submissions)
            if (!isPending && status == 'approved')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "$auraPoints Aura Points awarded",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // AI reason / comment
            if (aiReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smart_toy_outlined,
                            size: 16, color: Color(0xFF7B2CBF)),
                        const SizedBox(width: 6),
                        Text(
                          "AI Comment",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      aiReason,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Admin action form
            TextField(
              controller: pointsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Aura Points to Award",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(isPending ? "Approve" : "Re-approve"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B2CBF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: approveSubmission,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text("Reject"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: rejectSubmission,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 4),
            const Text(
              "Admin Actions",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text("Archive"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: adminArchive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text("Delete"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      side: BorderSide(color: Colors.red[800]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: adminDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'approved':
        color = Colors.green;
        label = 'Approved';
      case 'rejected':
        color = Colors.red;
        label = 'Rejected';
      case 'ai_error':
        color = Colors.orange;
        label = 'AI Error';
      default:
        color = Colors.blue;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
