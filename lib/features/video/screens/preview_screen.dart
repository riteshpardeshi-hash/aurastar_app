import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import '../../challenges/widgets/aura_submitted_popup.dart';
import '../../challenges/screens/post_score_action_screen.dart';

class PreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;
  final String challengeId;

  const PreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
    required this.challengeId,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late VideoPlayerController _controller;
  bool isUploading = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.videoPath),
    )..initialize().then((_) {
      setState(() {});
      _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool?> _showAuraSubmittedPopup(String submissionId) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => AuraSubmittedPopup(
        submissionId: submissionId,
        challengeTitle: widget.challengeTitle,
        challengeId: widget.challengeId,
      ),
    );
  }

  Future<void> _showLimitDialog() {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: Color(0xFF7B2CBF), size: 24),
            SizedBox(width: 10),
            Text(
              "Daily Limit Reached",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: const Text(
          "You've submitted 3 challenges today.\nYour limit resets at midnight. Come back tomorrow!",
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF7B2CBF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> uploadVideo() async {
    try {
      setState(() => isUploading = true);

      final user = FirebaseAuth.instance.currentUser;
      final file = File(widget.videoPath);

      // ── Daily submission limit check (max 3 per day) ──────────────────────
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final todayCount = await FirebaseFirestore.instance
          .collection('submissions')
          .where('userId', isEqualTo: user!.uid)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .count()
          .get();

      if ((todayCount.count ?? 0) >= 3) {
        setState(() => isUploading = false);
        if (!mounted) return;
        await _showLimitDialog();
        return;
      }
      // ─────────────────────────────────────────────────────────────────────

      // Fetch username for feed display
      String username = 'User';
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        username = userDoc.data()?['username'] as String? ??
            userDoc.data()?['name'] as String? ??
            'User';
      }

      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}";

      final ref = FirebaseStorage.instance
          .ref()
          .child('submissions')
          .child(user.uid)
          .child(fileName);

      await ref.putFile(file);
      final videoUrl = await ref.getDownloadURL();

      final docRef = await FirebaseFirestore.instance.collection('submissions').add({
        'userId': user.uid,
        'username': username,
        'challengeTitle': widget.challengeTitle,
        'challengeId': widget.challengeId,
        'videoUrl': videoUrl,
        'status': 'pending',
        'auraPoints': 0,
        'netAurasAwarded': 0,
        'isCountedForDailyAuras': false,
        'isPublic': false,
        'isArchived': false,
        'isDeleted': false,
        'starsCount': 0,
        'starredBy': [],
        'views': 0,
        'reach': 0,
        'createdAt': Timestamp.now(),
      });

      setState(() => isUploading = false);

      if (!mounted) return;
      await _showAuraSubmittedPopup(docRef.id);
      if (!mounted) return;

      // Navigate to post-score action screen regardless of scoring state
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PostScoreActionScreen(
            submissionId: docRef.id,
            challengeTitle: widget.challengeTitle,
            challengeId: widget.challengeId,
          ),
        ),
      );
    } catch (e) {
      setState(() => isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preview")),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          const SizedBox(height: 20),
          isUploading
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: uploadVideo,
                    child: const Text("Submit Video"),
                  ),
                ),
        ],
      ),
    );
  }
}
