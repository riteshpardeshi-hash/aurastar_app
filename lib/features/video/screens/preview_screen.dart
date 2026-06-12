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
  static const _purple = Color(0xFF7B2CBF);

  late VideoPlayerController _player;
  bool _playerReady = false;
  bool _isPlaying = false;

  // Upload state
  _UploadState _uploadState = _UploadState.idle;
  double _progress = 0; // 0.0 – 1.0

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _playerReady = true);
        _player.play();
        _player.setLooping(true);
        setState(() => _isPlaying = true);
      });
    _player.addListener(() {
      if (mounted) setState(() => _isPlaying = _player.value.isPlaying);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ── Upload ──────────────────────────────────────────────────────────────────

  Future<void> _upload() async {
    setState(() {
      _uploadState = _UploadState.uploading;
      _progress = 0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _uploadState = _UploadState.idle);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be signed in to upload.')),
          );
        }
        return;
      }
      final file = File(widget.videoPath);

      // Fetch username
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
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('submissions')
          .child(user.uid)
          .child(fileName);

      final task = ref.putFile(file);

      // Stream upload progress
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0 && mounted) {
          setState(() =>
              _progress = snap.bytesTransferred / snap.totalBytes);
        }
      });

      await task;

      final videoUrl = await ref.getDownloadURL();

      final docRef =
          await FirebaseFirestore.instance.collection('submissions').add({
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

      if (!mounted) return;
      setState(() => _uploadState = _UploadState.done);
      _player.pause();

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (_) => AuraSubmittedPopup(
          submissionId: docRef.id,
          challengeTitle: widget.challengeTitle,
          challengeId: widget.challengeId,
        ),
      );

      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _uploadState = _UploadState.failed);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _uploadState == _UploadState.uploading
                        ? null
                        : () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.challengeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Video preview
            Expanded(
              child: _playerReady
                  ? GestureDetector(
                      onTap: () {
                        _isPlaying ? _player.pause() : _player.play();
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _player.value.aspectRatio,
                            child: VideoPlayer(_player),
                          ),
                          if (!_isPlaying)
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.50),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 30),
                            ),
                        ],
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: _purple)),
            ),

            // Bottom section
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottom() {
    switch (_uploadState) {
      case _UploadState.idle:
        return _idleControls();
      case _UploadState.uploading:
        return _uploadingView();
      case _UploadState.failed:
        return _failedView();
      case _UploadState.done:
        return const SizedBox.shrink();
    }
  }

  // Idle — Submit / Retake buttons
  Widget _idleControls() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Looks good?',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Center(
                        child: Text('Retake',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _upload,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _purple,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _purple.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text('Submit for Aura Score',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // Uploading — progress bar with %
  Widget _uploadingView() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploading…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: _purple,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(_purple),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep app open • Failed upload = no attempt lost',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
          ],
        ),
      );

  // Failed — retry button, local file preserved
  Widget _failedView() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_off_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                const Text('Upload failed',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your attempt was not consumed. Tap retry when you\'re back online.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Center(
                        child: Text('Retake',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _upload,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text('Retry Upload',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

enum _UploadState { idle, uploading, failed, done }
