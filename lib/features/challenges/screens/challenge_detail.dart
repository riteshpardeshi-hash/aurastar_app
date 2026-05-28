import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../video/screens/preview_screen.dart';
import 'camera_screen.dart';

class ChallengeDetail extends StatefulWidget {
  final String title;
  final String instructions;
  final String videoUrl;
  final String challengeId;

  const ChallengeDetail({
    super.key,
    required this.title,
    required this.instructions,
    required this.videoUrl,
    required this.challengeId,
  });

  @override
  State<ChallengeDetail> createState() => _ChallengeDetailState();
}

class _ChallengeDetailState extends State<ChallengeDetail> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _liked = false;
  int _likeCount = 0;
  bool _likeLoading = false;

  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _loadLikes();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    await _videoController.initialize();
    if (mounted) {
      setState(() => _videoInitialized = true);
      _videoController.play();
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _videoController.dispose();
    super.dispose();
  }

  Future<void> _loadLikes() async {
    if (widget.challengeId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('challenges')
        .doc(widget.challengeId)
        .get();
    if (!doc.exists || !mounted) return;
    final likes = List<String>.from(doc.data()?['likes'] ?? []);
    setState(() {
      _liked = likes.contains(_uid);
      _likeCount = likes.length;
    });
  }

  Future<void> _toggleLike() async {
    if (widget.challengeId.isEmpty || _likeLoading) return;
    setState(() => _likeLoading = true);

    final ref = FirebaseFirestore.instance
        .collection('challenges')
        .doc(widget.challengeId);

    if (_liked) {
      await ref.update({'likes': FieldValue.arrayRemove([_uid])});
      if (mounted) setState(() { _liked = false; _likeCount--; });
    } else {
      await ref.update({'likes': FieldValue.arrayUnion([_uid])});
      if (mounted) setState(() { _liked = true; _likeCount++; });
    }

    if (mounted) setState(() => _likeLoading = false);
  }

  void _share() {
    Share.share('Check out this challenge on Aura: "${widget.title}" 🌟\n${widget.videoUrl}');
  }

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Widget _buildVideo() {
    if (!_videoInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _videoController.value.aspectRatio,
      child: VideoPlayer(_videoController),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        appBar: _isFullscreen ? null : AppBar(title: Text(widget.title)),
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _enterFullscreen,
                    child: SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!_isFullscreen) _buildVideo(),
                          if (_videoInitialized && !_isFullscreen)
                            const Positioned(
                              right: 8,
                              bottom: 8,
                              child: Icon(
                                Icons.fullscreen,
                                color: Colors.white70,
                                size: 28,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LikeButton(
                        liked: _liked,
                        count: _likeCount,
                        loading: _likeLoading,
                        onTap: _toggleLike,
                      ),
                      const SizedBox(width: 24),
                      _ShareButton(onTap: _share),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Instructions:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.instructions,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CameraScreen(
                                  challengeTitle: widget.title,
                                  challengeId: widget.challengeId,
                                ),
                              ),
                            );
                          },
                          child: const Text("Start Recording"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: 'Pick from gallery',
                        child: ElevatedButton(
                          onPressed: () async {
                            final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
                            if (picked == null || !context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PreviewScreen(
                                  videoPath: picked.path,
                                  challengeTitle: widget.title,
                                  challengeId: widget.challengeId,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          child: const Icon(Icons.photo_library_outlined),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_isFullscreen)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_videoController.value.isPlaying) {
                            _videoController.pause();
                          } else {
                            _videoController.play();
                          }
                          setState(() {});
                        },
                        child: Center(child: _buildVideo()),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 32),
                            onPressed: _exitFullscreen,
                          ),
                        ),
                      ),
                      if (_videoInitialized && !_videoController.value.isPlaying)
                        const Center(
                          child: IgnorePointer(
                            child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 64),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  final bool liked;
  final int count;
  final bool loading;
  final VoidCallback onTap;

  const _LikeButton({
    required this.liked,
    required this.count,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7B2CBF)),
                  )
                : Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(liked),
                    color: liked ? const Color(0xFFE0245E) : Colors.grey,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ShareButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const Row(
        children: [
          Icon(Icons.share, color: Color(0xFF7B2CBF), size: 24),
          SizedBox(width: 6),
          Text('Share', style: TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }
}
