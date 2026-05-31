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

  Future<void> uploadVideo() async {
    try {
      setState(() => isUploading = true);

      final user = FirebaseAuth.instance.currentUser!;
      final file = File(widget.videoPath);

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
