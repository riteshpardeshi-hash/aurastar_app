import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
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
    return {...s, 'status': submissionStatusFromApi(s)};
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
  // Archive/Delete removed — the backend has no per-submission archive or
  // delete endpoint yet (submissions live in the REST/Mongo API now, not
  // Firestore, so the old Firestore writes here always failed with
  // not-found). Re-add once that endpoint exists.

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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
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
              if (status != 'rejected') ...[
                const Text(
                  'Share your result',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 28),
                _buildInstagramAction(),
              ],
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
              color: AppColors.textMuted,
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
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                  color: AppColors.textFaint,
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
                        color: AppColors.textMuted, fontSize: 12, height: 1.35),
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
                      color: AppColors.textFaint,
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
