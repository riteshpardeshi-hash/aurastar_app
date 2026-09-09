import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/videos_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/theme/app_colors.dart';
import '../../video/widgets/video_player_widget.dart';

class UserVideoDetailScreen extends StatefulWidget {
  final int videoNumber;
  final String challengeTitle;
  final int auraPoints;
  final String videoUrl;
  final String status;
  final dynamic aiScore;
  final String aiReason;
  final bool reviewedByAI;
  final String videoId;

  const UserVideoDetailScreen({
    super.key,
    required this.videoNumber,
    required this.auraPoints,
    required this.videoUrl,
    required this.videoId,
    this.challengeTitle = '',
    this.status = 'pending',
    this.aiScore,
    this.aiReason = '',
    this.reviewedByAI = false,
  });

  @override
  State<UserVideoDetailScreen> createState() => _UserVideoDetailScreenState();
}

class _UserVideoDetailScreenState extends State<UserVideoDetailScreen> {
  bool _deleting = false;

  void _share() {
    Share.share('Check out my video submission on Aura! 🌟\n${widget.videoUrl}');
  }

  /// Points this delete will claw back from the wallet — only an approved
  /// video that actually earned Aura has any.
  int get _deductibleAura =>
      widget.status == 'approved' && widget.auraPoints > 0
          ? widget.auraPoints
          : 0;

  Future<void> _delete() async {
    final pts = _deductibleAura;
    // The backend does not reverse Aura on delete (openapi.yaml: DELETE
    // /videos/{id} is a bare soft-delete); VideosService tracks the lost
    // points locally and subtracts them from displayed balances. Warn the
    // user with the exact amount so the wallet drop isn't a surprise.
    final message = pts > 0
        ? 'This video earned you $pts Aura ${pts == 1 ? 'point' : 'points'}. '
            'Deleting it will permanently remove those $pts '
            '${pts == 1 ? 'point' : 'points'} from your wallet, and this '
            "can't be undone."
        : 'This will permanently remove your video. This action cannot be undone.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Video',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await VideosService().deleteVideo(widget.videoId, auraPoints: pts);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      // DELETE /videos/{id}'s documented failure modes are all specific
      // (403 "requires ownership", 400 "this is a challenge's reference
      // video", 404) — surface the backend's actual reason instead of a
      // generic "try again" that hides which one actually happened.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = widget.status == 'approved';
    final isPending = widget.status == 'pending';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.challengeTitle.trim().isNotEmpty
              ? widget.challengeTitle
              : "Video ${widget.videoNumber}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ~65% of the screen, portrait — these are always the user's own
            // portrait-locked recordings, so give them a tall box they
            // actually fill instead of a short, wide letterboxed strip.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.65,
                width: double.infinity,
                color: Colors.black,
                child: VideoPlayerWidget(widget.videoUrl, forcePortrait: true),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: _ShareButton(onTap: _share)),
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
