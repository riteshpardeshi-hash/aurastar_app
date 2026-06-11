import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../dashboard/dashboard.dart';

class PostScoreActionScreen extends StatefulWidget {
  final String submissionId;
  final String challengeTitle;
  final String challengeId;

  const PostScoreActionScreen({
    super.key,
    required this.submissionId,
    required this.challengeTitle,
    required this.challengeId,
  });

  @override
  State<PostScoreActionScreen> createState() => _PostScoreActionScreenState();
}

class _PostScoreActionScreenState extends State<PostScoreActionScreen> {
  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  Map<String, dynamic>? _submission;
  bool _loading = true;
  bool _actioning = false;

  @override
  void initState() {
    super.initState();
    _fetchSubmission();
  }

  Future<void> _fetchSubmission() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('submissions')
          .doc(widget.submissionId)
          .get();
      if (mounted) {
        setState(() {
          _submission = doc.data();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _share() async {
    setState(() => _actioning = true);
    try {
      await FirebaseFirestore.instance
          .collection('submissions')
          .doc(widget.submissionId)
          .update({'isPublic': true, 'isArchived': false});
      _navigateToDashboard();
    } catch (_) {
      if (!mounted) return;
      setState(() => _actioning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.')),
      );
    }
  }

  Future<void> _archive() async {
    final ok = await _confirm(
      title: 'Archive Video',
      body: 'Your video will be private. Your Auras are kept.',
      confirmLabel: 'Archive',
      confirmColor: Colors.orange,
    );
    if (!ok || !mounted) return;
    setState(() => _actioning = true);
    try {
      await FirebaseFirestore.instance
          .collection('submissions')
          .doc(widget.submissionId)
          .update({'isArchived': true, 'isPublic': false});
      _navigateToDashboard();
    } catch (_) {
      if (!mounted) return;
      setState(() => _actioning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.')),
      );
    }
  }

  Future<void> _delete() async {
    final auraPoints = (_submission?['auraPoints'] as num?)?.toInt() ?? 0;
    final netAwarded = (_submission?['netAurasAwarded'] as num?)?.toInt() ?? auraPoints;
    final deduct = netAwarded > 0 ? netAwarded : auraPoints;

    final ok = await _confirm(
      title: 'Delete Video',
      body: deduct > 0
          ? 'This will permanently remove your video and deduct $deduct Aura Points from your balance.'
          : 'This will permanently remove your video.',
      confirmLabel: 'Delete',
      confirmColor: Colors.redAccent,
    );
    if (!ok || !mounted) return;

    setState(() => _actioning = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.update(
        db.collection('submissions').doc(widget.submissionId),
        {'isDeleted': true, 'isPublic': false, 'isArchived': false, 'isCountedForDailyAuras': false},
      );
      if (deduct > 0 && user != null) {
        batch.update(
          db.collection('users').doc(user.uid),
          {'totalRewards': FieldValue.increment(-deduct)},
        );
        batch.set(db.collection('auraTransactions').doc(), {
          'userId': user.uid,
          'amount': -deduct,
          'type': 'deleted_video_deduction',
          'sourceId': widget.submissionId,
          'description': 'Video deleted — $deduct Auras deducted',
          'createdAt': Timestamp.now(),
        });
      }
      await batch.commit();
      _navigateToDashboard();
    } catch (_) {
      if (!mounted) return;
      setState(() => _actioning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action failed. Please try again.')),
      );
    }
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (route) => false,
    );
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
            backgroundColor: const Color(0xFF12102A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(body, style: const TextStyle(color: Colors.white70, height: 1.4)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading || _actioning) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    final score = (_submission?['aiScore'] as num?)?.toInt();
    final netAwarded = (_submission?['netAurasAwarded'] as num?)?.toInt() ??
        (_submission?['auraPoints'] as num?)?.toInt() ??
        0;
    final isBest = _submission?['isBestForChallenge'] as bool? ?? false;
    final status = _submission?['status'] as String? ?? 'pending';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Your Result'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _navigateToDashboard,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (score != null && status != 'pending')
                _buildScoreCard(score, netAwarded, isBest, status),
              const SizedBox(height: 28),
              if (!isBest && status == 'approved')
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.archive_outlined, color: Colors.orange, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Not your best — this has been archived automatically and will be deleted in 7 days.',
                            style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(
                isBest ? 'What do you want to do\nwith your video?' : 'Your video is archived',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              if (isBest)
                _buildAction(
                  label: 'Share Publicly',
                  subtitle: 'Visible to the community. Eligible for leaderboards & stars.',
                  icon: Icons.public_rounded,
                  gradient: const [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                  onTap: _share,
                ),
              if (isBest) const SizedBox(height: 12),
              _buildAction(
                label: 'Archive (Keep Private)',
                subtitle: 'Only you can see it. Your Auras are kept.',
                icon: Icons.archive_outlined,
                gradient: const [Color(0xFF374151), Color(0xFF1F2937)],
                onTap: _archive,
              ),
              const SizedBox(height: 12),
              _buildAction(
                label: 'Delete Video',
                subtitle: netAwarded > 0
                    ? 'Removes video and deducts $netAwarded Aura Points.'
                    : 'Removes your video permanently.',
                icon: Icons.delete_outline_rounded,
                gradient: const [Color(0xFF7F1D1D), Color(0xFF450A0A)],
                onTap: _delete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(int score, int netAwarded, bool isBest, String status) {
    final approved = status == 'approved';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: approved
              ? const [Color(0xFF1A0533), Color(0xFF3A1C71)]
              : const [Color(0xFF1A0000), Color(0xFF2E0000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: approved
              ? _accent.withValues(alpha: 0.5)
              : Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            '$score',
            style: TextStyle(
              color: approved ? const Color(0xFFFFD700) : Colors.redAccent,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const Text(
            'AURA SCORE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (approved) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isBest
                    ? Colors.greenAccent.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isBest
                      ? Colors.greenAccent.withValues(alpha: 0.35)
                      : Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                isBest
                    ? '+$netAwarded Auras earned ✓ New best!'
                    : 'Not your best — no Auras earned',
                style: TextStyle(
                  color: isBest ? Colors.greenAccent : Colors.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!approved) ...[
            const SizedBox(height: 10),
            const Text(
              'Keep trying — you\'ll get it!',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAction({
    required String label,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12, height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
          ],
        ),
      ),
    );
  }
}
