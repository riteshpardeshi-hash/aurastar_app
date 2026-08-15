import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../features/challenges/widgets/achievement_card.dart'
    show kChallengeBaseUrl;
import '../../../shared/theme/app_colors.dart';
import '../admin/creator_admin_screen.dart';

class CreatorEntriesScreen extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;

  const CreatorEntriesScreen({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
  });

  @override
  State<CreatorEntriesScreen> createState() => _CreatorEntriesScreenState();
}

class _CreatorEntriesScreenState extends State<CreatorEntriesScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  String _sort = 'best'; // 'best' | 'latest'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Entries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(widget.challengeTitle,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Filter toggle
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SortToggle(
              sort: _sort,
              onChanged: (s) => setState(() => _sort = s),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('submissions')
            .where('challengeId', isEqualTo: widget.challengeId)
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_library_outlined,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  const Text('No approved entries yet',
                      style: TextStyle(color: AppColors.textFaint)),
                ],
              ),
            );
          }

          // Sort
          final sorted = [...docs];
          if (_sort == 'best') {
            sorted.sort((a, b) {
              final aScore =
                  ((a.data() as Map<String, dynamic>)['aiScore'] as num?) ?? 0;
              final bScore =
                  ((b.data() as Map<String, dynamic>)['aiScore'] as num?) ?? 0;
              return bScore.compareTo(aScore);
            });
          } else {
            sorted.sort((a, b) {
              final aTs = (a.data() as Map<String, dynamic>)['createdAt']
                  as Timestamp?;
              final bTs = (b.data() as Map<String, dynamic>)['createdAt']
                  as Timestamp?;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              return bTs.compareTo(aTs);
            });
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final data = sorted[i].data() as Map<String, dynamic>;
              final score = (data['aiScore'] as num?)?.toInt() ?? 0;
              final userId = data['userId']?.toString() ?? '';
              final ts    = data['createdAt'] as Timestamp?;
              final subId = sorted[i].id;

              return _EntryRow(
                rank:    i + 1,
                score:   score,
                userId:  userId,
                ts:      ts,
                videoUrl: data['videoUrl'] as String? ?? '',
                feedback: data['aiReason'] as String? ?? '',
                subId:   subId,
                onShareBlocked:    () => _showBlockedSheet(context, isDownload: false),
                onDownloadBlocked: () => _showBlockedSheet(context, isDownload: true),
              );
            },
          );
        },
      ),
    );
  }

  void _showBlockedSheet(BuildContext context, {required bool isDownload}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),

            // Icon + title
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDownload
                    ? Icons.download_outlined
                    : Icons.share_outlined,
                color: Colors.redAccent, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              isDownload ? 'Downloads Not Allowed' : 'Sharing Not Allowed',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ClashDisplay'),
            ),
            const SizedBox(height: 10),
            Text(
              isDownload
                  ? 'Player videos cannot be downloaded. This protects player privacy and is required by platform policy. Violations may result in a creator strike.'
                  : 'Player submission videos cannot be shared externally. Respect player privacy by sharing the challenge link to grow participation instead.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
            ),

            // Policy detail row
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF9B4DFF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDownload
                          ? 'Screens are protected where possible. Use analytics to review performance instead.'
                          : 'Share challenge link only — no raw player video is ever shared publicly.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Primary CTA
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  if (isDownload) {
                    // View Analytics
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreatorAdminScreen()),
                    );
                  } else {
                    // Share challenge link (not the player video)
                    final link =
                        '$kChallengeBaseUrl/${widget.challengeId}';
                    Share.share(
                      'Join my challenge on Aura Arena! 🔥\n\n'
                      '${widget.challengeTitle}\n\n'
                      'Can you beat it? 💪\n$link',
                      subject: widget.challengeTitle,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDownload
                      ? const Color(0xFF1E3A5F)
                      : _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isDownload
                          ? Icons.bar_chart_rounded
                          : Icons.link_rounded,
                      size: 18),
                    const SizedBox(width: 8),
                    Text(isDownload
                        ? 'View Analytics Instead'
                        : 'Share Challenge Link'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Dismiss
            SizedBox(
              width: double.infinity,
              height: 42,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
                child: const Text('Dismiss',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort toggle ───────────────────────────────────────────────────────────────

class _SortToggle extends StatelessWidget {
  final String sort;
  final ValueChanged<String> onChanged;

  const _SortToggle({required this.sort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _pill('Best',   'best'),
          _pill('Latest', 'latest'),
        ],
      ),
    );
  }

  Widget _pill(String label, String value) {
    final sel = sort == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF7B2CBF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: sel ? Colors.white : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Entry row ─────────────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  final int    rank;
  final int    score;
  final String userId;
  final Timestamp? ts;
  final String videoUrl;
  final String feedback;
  final String subId;
  final VoidCallback onShareBlocked;
  final VoidCallback onDownloadBlocked;

  const _EntryRow({
    required this.rank,
    required this.score,
    required this.userId,
    required this.ts,
    required this.videoUrl,
    required this.feedback,
    required this.subId,
    required this.onShareBlocked,
    required this.onDownloadBlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 75
        ? const Color(0xFF22C55E)
        : score >= 40
            ? const Color(0xFFF59E0B)
            : Colors.redAccent;

    final dateStr = ts != null
        ? _fmt(ts!.toDate())
        : '';

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF100A20),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: TextStyle(
                    color: rank <= 3
                        ? const Color(0xFFD4A8FF)
                        : AppColors.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // Score badge
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor.withValues(alpha: 0.40)),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                      color: scoreColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Handle / time
            Expanded(
              child: FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get(),
                builder: (_, snap) {
                  final d = snap.data?.data() as Map<String, dynamic>? ?? {};
                  final handle = d['username'] as String? ?? 'player';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$handle',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      if (dateStr.isNotEmpty)
                        Text(dateStr,
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                    ],
                  );
                },
              ),
            ),
            // Chevron
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EntryDetailSheet(
        videoUrl:          videoUrl,
        score:             score,
        feedback:          feedback,
        subId:             subId,
        onShareBlocked:    onShareBlocked,
        onDownloadBlocked: onDownloadBlocked,
      ),
    );
  }

  String _fmt(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }
}

// ── Entry detail bottom sheet ─────────────────────────────────────────────────

class _EntryDetailSheet extends StatefulWidget {
  final String videoUrl;
  final int    score;
  final String feedback;
  final String subId;
  final VoidCallback onShareBlocked;
  final VoidCallback onDownloadBlocked;

  const _EntryDetailSheet({
    required this.videoUrl,
    required this.score,
    required this.feedback,
    required this.subId,
    required this.onShareBlocked,
    required this.onDownloadBlocked,
  });

  @override
  State<_EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<_EntryDetailSheet> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _isPlaying   = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl.isNotEmpty) {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        ..initialize().then((_) {
          if (mounted) setState(() => _initialized = true);
          _ctrl!.addListener(_onUpdate);
        });
    }
  }

  void _onUpdate() {
    if (mounted) {
      setState(() => _isPlaying = _ctrl?.value.isPlaying ?? false);
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = widget.score >= 75
        ? const Color(0xFF22C55E)
        : widget.score >= 40
            ? const Color(0xFFF59E0B)
            : Colors.redAccent;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),

            // Video player
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_initialized)
                      AspectRatio(
                        aspectRatio: correctedVideoAspectRatio(_ctrl!.value),
                        child: VideoPlayer(_ctrl!),
                      )
                    else
                      const CircularProgressIndicator(
                          color: Color(0xFF7B2CBF)),

                    // Play/pause overlay
                    if (_initialized)
                      GestureDetector(
                        onTap: () {
                          if (_isPlaying) {
                            _ctrl!.pause();
                          } else {
                            _ctrl!.play();
                          }
                        },
                        child: AnimatedOpacity(
                          opacity: _isPlaying ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 54, height: 54,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white, size: 32),
                          ),
                        ),
                      ),

                    // Privacy badge
                    Positioned(
                      bottom: 10, right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                color: Colors.white70, size: 11),
                            const SizedBox(width: 4),
                            const Text('Private entry',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Score
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: scoreColor.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, color: scoreColor, size: 16),
                        const SizedBox(width: 6),
                        Text('${widget.score}',
                            style: TextStyle(
                                color: scoreColor,
                                fontSize: 22,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 4),
                        Text('/ 100',
                            style: TextStyle(
                                color: scoreColor.withValues(alpha: 0.60),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Report button
                  GestureDetector(
                    onTap: () => _confirmReport(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.30)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.flag_outlined,
                              color: Colors.redAccent, size: 14),
                          SizedBox(width: 5),
                          Text('Report',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Feedback
            if (widget.feedback.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(widget.feedback,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ),
              ),
            ],

            // Privacy notice
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.white24, size: 14),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Player entry • No share or download • Visible only to you and admin',
                        style: TextStyle(color: AppColors.textFaint, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Blocked action buttons (visible but blocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onShareBlocked,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share_outlined,
                                color: Colors.white24, size: 14),
                            const SizedBox(width: 6),
                            const Text('Share',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                            const SizedBox(width: 4),
                            const Icon(Icons.block_rounded,
                                color: Colors.white24, size: 11),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onDownloadBlocked,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.download_outlined,
                                color: Colors.white24, size: 14),
                            const SizedBox(width: 6),
                            const Text('Download',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 12)),
                            const SizedBox(width: 4),
                            const Icon(Icons.block_rounded,
                                color: Colors.white24, size: 11),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReport(BuildContext context) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A2E),
        title: const Text('Report Entry',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'Flag this entry for admin review? Use this for safety or policy violations.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(dlgCtx);
              await FirebaseFirestore.instance
                  .collection('reports')
                  .add({
                'submissionId': widget.subId,
                'reason':       'creator_flag',
                'createdAt':    FieldValue.serverTimestamp(),
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reported to admin'),
                    backgroundColor: Color(0xFF1A0A2E),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Report',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
