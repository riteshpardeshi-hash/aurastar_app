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

  int _netAurasAwarded = 0;
  bool _isCountedForDailyAuras = false;
  String _challengeId = '';
  bool _deleting = false;

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
    final aura = (data['auraPoints'] as num?)?.toInt() ?? 0;
    final netAwarded = (data['netAurasAwarded'] as num?)?.toInt() ?? aura;
    setState(() {
      _starred = starredBy.contains(_uid);
      _starsCount = (data['starsCount'] as num?)?.toInt() ?? starredBy.length;
      _ownerId = data['userId'] as String? ?? '';
      _netAurasAwarded = netAwarded;
      _isCountedForDailyAuras = data['isCountedForDailyAuras'] as bool? ?? false;
      _challengeId = data['challengeId'] as String? ?? '';
    });
  }

  Future<void> _toggleStar() async {
    if (widget.submissionId.isEmpty || _starLoading || _uid.isEmpty) return;
    setState(() => _starLoading = true);

    final delta = _starred ? -1 : 1;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection('submissions').doc(widget.submissionId), {
      'starredBy': _starred
          ? FieldValue.arrayRemove([_uid])
          : FieldValue.arrayUnion([_uid]),
      'starsCount': FieldValue.increment(delta),
    });
    if (_ownerId.isNotEmpty && _ownerId != _uid) {
      batch.update(db.collection('users').doc(_ownerId),
          {'starsReceived': FieldValue.increment(delta)});
    }

    try {
      await batch.commit();
      if (mounted) {
        setState(() {
          _starred = !_starred;
          _starsCount += delta;
          _starLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _starLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update star. Try again.')),
        );
      }
    }
  }

  void _share() {
    Share.share('Check out my video submission on Aura! 🌟\n${widget.videoUrl}');
  }

  Future<void> _delete() async {
    final deduct = _isCountedForDailyAuras && _netAurasAwarded > 0 ? _netAurasAwarded : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video'),
        content: Text(
          deduct > 0
              ? 'This will permanently remove your video and deduct $deduct Aura Points from your balance.'
              : 'This will permanently remove your video. Your Aura Points are kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final db = FirebaseFirestore.instance;
    try {
      await db.runTransaction((txn) async {
        final subRef = db.collection('submissions').doc(widget.submissionId);
        txn.update(subRef, {
          'isDeleted': true,
          'isPublic': false,
          'isArchived': false,
          'isCountedForDailyAuras': false,
          'deletedAt': Timestamp.now(),
        });
        if (deduct > 0 && _uid.isNotEmpty) {
          txn.update(db.collection('users').doc(_uid), {
            'totalRewards': FieldValue.increment(-deduct),
          });
          txn.set(db.collection('auraTransactions').doc(), {
            'userId': _uid,
            'amount': -deduct,
            'type': 'video_deleted',
            'sourceId': widget.submissionId,
            'description': 'Video deleted — $deduct Auras reversed',
            'createdAt': Timestamp.now(),
          });
          if (_challengeId.isNotEmpty) {
            final progressRef = db
                .collection('userChallengeProgress')
                .doc('${_uid}_$_challengeId');
            txn.delete(progressRef);
          }
        }
      });
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = widget.status == 'approved';
    final isPending = widget.status == 'pending';

    return Scaffold(
      appBar: AppBar(
        title: Text("Video ${widget.videoNumber}"),
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete video',
              onPressed: _delete,
            ),
        ],
      ),
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
