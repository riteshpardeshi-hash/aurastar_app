import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/challenges_service.dart';
import '../../dashboard/dashboard.dart';

class PostScoreActionScreen extends StatefulWidget {
  final String submissionId;
  final String challengeTitle;
  final String challengeId;
  final Map<String, dynamic>? submissionData;

  const PostScoreActionScreen({
    super.key,
    required this.submissionId,
    required this.challengeTitle,
    required this.challengeId,
    this.submissionData,
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
  bool _isInstagramSharing = false;
  final _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.submissionData != null) {
      _submission = _normaliseApiSubmission(widget.submissionData!);
      _loading = false;
    } else {
      _fetchSubmission();
    }
  }

  Map<String, dynamic> _normaliseApiSubmission(Map<String, dynamic> s) {
    final verdict = s['verdict'] as String? ?? '';
    return {
      ...s,
      'status': verdict == 'PASS'
          ? 'approved'
          : verdict == 'FAIL'
              ? 'rejected'
              : 'ai_error',
    };
  }

  Future<void> _fetchSubmission() async {
    try {
      final data = await ChallengesService().fetchMySubmission(widget.challengeId);
      if (mounted) {
        setState(() {
          _submission = data != null ? _normaliseApiSubmission(data) : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

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

  Future<void> _shareToInstagramStory() async {
    if (_isInstagramSharing) return;
    setState(() => _isInstagramSharing = true);
    try {
      Uint8List? bytes;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }
      if (bytes != null) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: 'aura_story.png')],
        );
      } else {
        await Share.share(
          'I just scored on "${widget.challengeTitle}" on Aura Arena! 🌟\n'
          'https://aura-app-efae1.web.app/challenge/${widget.challengeId}',
        );
      }
    } catch (_) {
      // share cancelled or failed — ignore
    } finally {
      if (mounted) setState(() => _isInstagramSharing = false);
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
                RepaintBoundary(
                  key: _cardKey,
                  child: _buildScoreCard(score, netAwarded, isBest, status),
                ),
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
              const Text(
                'What do you want to do\nwith your video?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              _buildAction(
                label: 'Archive (Keep Private)',
                subtitle: 'Only you can see it. Your Auras are kept.',
                icon: Icons.archive_outlined,
                gradient: const [Color(0xFF374151), Color(0xFF1F2937)],
                onTap: _archive,
              ),
              const SizedBox(height: 12),
              _buildInstagramAction(),
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
    final rawBreakdown = _submission?['scoreBreakdown'];
    final breakdown = rawBreakdown is Map ? rawBreakdown : null;

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

          // ── Score breakdown ─────────────────────────────────────────────
          if (breakdown != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white12, thickness: 0.8),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'BREAKDOWN',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SubScoreBar(
              label: 'Style',
              weight: '30%',
              score: (breakdown['style'] as num?)?.toInt() ?? score,
              color: const Color(0xFF4B6EF6),
            ),
            _SubScoreBar(
              label: 'Match',
              weight: '30%',
              score: (breakdown['match'] as num?)?.toInt() ?? score,
              color: const Color(0xFF9B4DCA),
            ),
            _SubScoreBar(
              label: 'Confidence',
              weight: '20%',
              score: (breakdown['confidence'] as num?)?.toInt() ?? score,
              color: const Color(0xFFFF6B9D),
            ),
            _SubScoreBar(
              label: 'Finish',
              weight: '20%',
              score: (breakdown['finish'] as num?)?.toInt() ?? score,
              color: const Color(0xFF06B6D4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstagramAction() {
    return GestureDetector(
      onTap: _isInstagramSharing ? null : _shareToInstagramStory,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: _isInstagramSharing
                ? const [Color(0xFF2A1040), Color(0xFF1A1030)]
                : const [Color(0xFF5C1A7A), Color(0xFF9B1A1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            _isInstagramSharing
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        color: Colors.white70, strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 26),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share to Instagram Story',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Share your score card as an Instagram Story.',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white30, size: 16),
          ],
        ),
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

// ── Animated sub-score bar ─────────────────────────────────────────────────────

class _SubScoreBar extends StatelessWidget {
  final String label;
  final String weight;
  final int score;
  final Color color;

  const _SubScoreBar({
    required this.label,
    required this.weight,
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    weight,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Text(
                '$score',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: score / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, value, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
