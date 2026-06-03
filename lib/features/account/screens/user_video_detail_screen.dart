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

  bool _starred = false;
  int _starsCount = 0;
  bool _starLoading = false;
  String _ownerId = '';

  @override
  void initState() {
    super.initState();
    _loadStars();
  }

  Future<void> _loadStars() async {
    if (widget.submissionId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId)
        .get();
    if (!doc.exists || !mounted) return;
    final data = doc.data()!;
    final starredBy = List<String>.from(data['starredBy'] ?? []);
    setState(() {
      _starred = starredBy.contains(_uid);
      _starsCount = (data['starsCount'] as num?)?.toInt() ?? starredBy.length;
      _ownerId = data['userId'] as String? ?? '';
    });
  }

  Future<void> _toggleStar() async {
    if (widget.submissionId.isEmpty || _starLoading) return;
    setState(() => _starLoading = true);

    final ref = FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId);
    final delta = _starred ? -1 : 1;

    await ref.update({
      'starredBy': _starred
          ? FieldValue.arrayRemove([_uid])
          : FieldValue.arrayUnion([_uid]),
      'starsCount': FieldValue.increment(delta),
    });

    // Update owner's starsReceived (skip own videos)
    if (_ownerId.isNotEmpty && _ownerId != _uid) {
      FirebaseFirestore.instance.collection('users').doc(_ownerId).update({
        'starsReceived': FieldValue.increment(delta),
      });
    }

    if (mounted) {
      setState(() {
        _starred = !_starred;
        _starsCount += delta;
        _starLoading = false;
      });
    }
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
                _StarButton(
                  starred: _starred,
                  count: _starsCount,
                  loading: _starLoading,
                  onTap: _toggleStar,
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

class _StarButton extends StatelessWidget {
  final bool starred;
  final int count;
  final bool loading;
  final VoidCallback onTap;

  const _StarButton({
    required this.starred,
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF7B2CBF)),
                  )
                : Icon(
                    starred ? Icons.star_rounded : Icons.star_outline_rounded,
                    key: ValueKey(starred),
                    color: starred ? const Color(0xFFFFD700) : Colors.grey,
                    size: 28,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: const TextStyle(fontSize: 13, color: Colors.white54),
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
