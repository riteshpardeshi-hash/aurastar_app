import 'package:flutter/material.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'user_video_detail_screen.dart';

class AllVideosScreen extends StatefulWidget {
  const AllVideosScreen({super.key});

  @override
  State<AllVideosScreen> createState() => _AllVideosScreenState();
}

class _AllVideosScreenState extends State<AllVideosScreen> {
  static const _bg = Color(0xFF0D0D1A);
  static const _accent = Color(0xFF7B2CBF);

  List<Map<String, dynamic>> _videos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await AuthApiService().fetchMyVideos(limit: 100);
    if (mounted) {
      setState(() {
        _videos = data.map(_normaliseSubmission).toList();
        _loading = false;
      });
    }
  }

  static Map<String, dynamic> _normaliseSubmission(Map<String, dynamic> s) {
    final submissionId = s['_id'] as String? ?? s['id'] as String? ?? '';
    // /profile/videos returns the Video document itself — its top-level
    // `status` (active/inactive) is the video's own lifecycle, unrelated to
    // AI scoring, which is nested under `submission`. Fall back to `s`
    // itself for a video with no submission yet (still pending).
    final submission = s['submission'] as Map<String, dynamic>? ?? s;
    return {
      // The Submission and Video are distinct backend documents — DELETE
      // /videos/{id} needs the Video's own id. Fall back to the submission
      // id if the API ever omits videoId (delete would then 404 loudly
      // rather than silently corrupt the wrong document).
      'videoId': s['videoId'] as String? ?? submissionId,
      'videoUrl': s['videoUrl'] as String? ?? '',
      'status': submissionStatusFromApi(submission),
      // See my_account_screen.dart's _normaliseSubmission: `/profile/videos`'s
      // nested `submission` omits `auraPoints`; openapi.yaml defines it as
      // "Raw aiScore stored on the submission record", so aiScore is the
      // correct fallback.
      'auraPoints': (submission['auraPoints'] as num?)?.toInt() ??
          (submission['aiScore'] as num?)?.toInt() ??
          0,
      'aiScore': submission['aiScore'],
      'aiReason': submission['feedback'] as String? ??
          submission['improvementTip'] as String? ??
          submission['aiReason'] as String? ??
          '',
      'reviewedByAI': submission['reviewedByAI'] as bool? ?? true,
    };
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'ai_error':
        return 'Error';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('My Videos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white10),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              color: _accent,
              onRefresh: _load,
              child: _videos.isEmpty ? _buildEmpty(context) : _buildGrid(),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_library_outlined,
                      color: Colors.white.withValues(alpha: 0.15), size: 64),
                  const SizedBox(height: 20),
                  const Text('No videos yet',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, i) {
        final data = _videos[i];
        final videoUrl = data['videoUrl'] as String;
        final status = data['status'] as String;
        final auraPoints = data['auraPoints'] as int;
        final aiScore = data['aiScore'];
        final aiReason = data['aiReason'] as String;
        final reviewedByAI = data['reviewedByAI'] as bool;
        final videoId = data['videoId'] as String;

        final statusColor = _statusColor(status);
        final statusLabel = _statusLabel(status);

        return GestureDetector(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserVideoDetailScreen(
                  videoNumber: i + 1,
                  auraPoints: auraPoints,
                  videoUrl: videoUrl,
                  status: status,
                  aiScore: aiScore,
                  aiReason: aiReason,
                  reviewedByAI: reviewedByAI,
                  videoId: videoId,
                ),
              ),
            );
            if (result == 'deleted') _load();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (status == 'approved')
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.diamond,
                              color: Color(0xFFD4A8FF), size: 10),
                          const SizedBox(width: 3),
                          Text(
                            '+$auraPoints',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
