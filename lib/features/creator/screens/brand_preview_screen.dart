import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import 'creator_challenge_submitted_screen.dart';

class BrandPreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;
  final String description;
  final String instructions;

  const BrandPreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
  });

  @override
  State<BrandPreviewScreen> createState() => _BrandPreviewScreenState();
}

class _BrandPreviewScreenState extends State<BrandPreviewScreen> {
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

  Future<void> submitChallenge() async {
    try {
      setState(() => isUploading = true);

      final user = FirebaseAuth.instance.currentUser;
      final file = File(widget.videoPath);

      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}";

      final ref = FirebaseStorage.instance
          .ref()
          .child('creator_videos')
          .child(user!.uid)
          .child(fileName);

      await ref.putFile(file);
      final videoUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('creator_requests').add({
        'title': widget.challengeTitle,
        'description': widget.description,
        'instructions': widget.instructions,
        'videoUrl': videoUrl,
        'creatorId': user.uid,
        'status': 'pending',
        'rejectionReason': '',
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CreatorChallengeSubmittedScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void recordAgain() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preview Video")),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isUploading ? null : submitChallenge,
                    child: isUploading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Submit"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isUploading ? null : recordAgain,
                    child: const Text("Record Again"),
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
