import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../video/widgets/video_player_widget.dart';

class UserVideoDetailScreen extends StatefulWidget {
  final int videoNumber;
  final int auraPoints;
  final String videoUrl;
  final String status;
  final dynamic aiScore;
  final String aiReason;
  final bool reviewedByAI;
  final String submissionId;

  const UserVideoDetailScreen({
    super.key,
    required this.videoNumber,
    required this.auraPoints,
    required this.videoUrl,
    required this.submissionId,
    this.status = 'pending',
    this.aiScore,
    this.aiReason = '',
    this.reviewedByAI = false,
  });

  @override
  State<UserVideoDetailScreen> createState() => _UserVideoDetailScreenState();
}

class _UserVideoDetailScreenState extends State<UserVideoDetailScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _liked = false;
  int _likeCount = 0;
  bool _likeLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    if (widget.submissionId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId)
        .get();
    if (!doc.exists || !mounted) return;
    final likes = List<String>.from(doc.data()?['likes'] ?? []);
    setState(() {
      _liked = likes.contains(_uid);
      _likeCount = likes.length;
    });
  }

  Future<void> _toggleLike() async {
    if (widget.submissionId.isEmpty || _likeLoading) return;
    setState(() => _likeLoading = true);

    final ref = FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId);

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
    Share.share('Check out my video submission on Aura! 🌟\n${widget.videoUrl}');
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = widget.status == 'approved';
    final isPending = widget.status == 'pending';

    return Scaffold(
      appBar: AppBar(title: Text("Video ${widget.videoNumber}")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: VideoPlayerWidget(widget.videoUrl),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LikeButton(
                  liked: _liked,
                  count: _likeCount,
                  loading: _likeLoading,
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 32),
                _ShareButton(onTap: _share),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPending)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF7B2CBF),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "AI is reviewing your video...",
                            style: TextStyle(
                              color: Color(0xFF7B2CBF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      Row(
                        children: [
                          Icon(
                            isApproved ? Icons.check_circle : Icons.cancel,
                            color: isApproved ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isApproved ? "Approved" : "Rejected",
                            style: TextStyle(
                              color: isApproved ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      if (widget.reviewedByAI && widget.aiScore != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7B2CBF)),
                            const SizedBox(width: 6),
                            Text(
                              "AI Score: ${widget.aiScore} / 100",
                              style: const TextStyle(
                                color: Color(0xFF7B2CBF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (isApproved) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.stars, color: Colors.deepPurple, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              "+${widget.auraPoints} Aura Points earned",
                              style: const TextStyle(
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.aiReason.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          "AI Feedback",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.aiReason,
                          style: const TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ],
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
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7B2CBF)),
                  )
                : Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(liked),
                    color: liked ? const Color(0xFFE0245E) : Colors.grey,
                    size: 28,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
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
      child: const Column(
        children: [
          Icon(Icons.share, color: Color(0xFF7B2CBF), size: 28),
          SizedBox(height: 4),
          Text('Share', style: TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }
}
