import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../shared/theme/app_colors.dart';
import 'creator_challenge_submitted_screen.dart';

class BrandPreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;
  final String description;
  final String instructions;
  final String difficulty;
  final String categoryId;
  final List<String> instructionSteps;

  const BrandPreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
    required this.categoryId,
    this.difficulty = 'Medium',
    this.instructionSteps = const [],
  });

  @override
  State<BrandPreviewScreen> createState() => _BrandPreviewScreenState();
}

class _BrandPreviewScreenState extends State<BrandPreviewScreen> {
  late VideoPlayerController _controller;
  bool _isUploading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isUploading = true;
      _progress = 0;
    });

    try {
      final service = ChallengesService();

      // Step 1: get presigned S3 URL + claim an unclaimed Video placeholder
      final presign = await service.presignChallenge();
      final uploadUrl = presign['uploadUrl'] as String;
      final videoId = presign['videoId'] as String;

      // Step 2: upload to S3
      await ApiClient().uploadToS3(
        uploadUrl,
        File(widget.videoPath),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p * 0.9);
        },
      );

      // Step 3: create challenge
      if (mounted) setState(() => _progress = 0.95);
      final instructions = widget.instructionSteps.isNotEmpty
          ? widget.instructionSteps
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value}')
              .join('\n')
          : widget.instructions;

      await service.createChallenge(
        title: widget.challengeTitle,
        description: widget.description,
        instructions: instructions,
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        videoId: videoId,
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => const CreatorChallengeSubmittedScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _progress = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submission failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preview Video')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: correctedVideoAspectRatio(_controller.value),
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isUploading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
                          child: const Text('Submit'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Record Again'),
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
