import 'package:flutter/material.dart';
import '../../../core/services/auth_api_service.dart';
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
    final verdict = s['verdict'] as String?;
    final rawStatus = s['status'] as String?;
    final status = verdict != null
        ? (verdict == 'PASS'
            ? 'approved'
            : verdict == 'FAIL'
                ? 'rejected'
                : 'ai_error')
        : rawStatus ?? 'pending';
    return {
      'submissionId': s['_id'] as String? ?? s['id'] as String? ?? '',
      'videoUrl': s['videoUrl'] as String? ?? '',
      'status': status,
      'auraPoints': (s['auraPoints'] as num?)?.toInt() ?? 0,
      'aiScore': s['aiScore'],
      'aiReason': s['feedback'] as String? ?? s['aiReason'] as String? ?? '',
      'reviewedByAI': s['reviewedByAI'] as bool? ?? true,
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
          : _videos.isEmpty
              ? _buildEmpty()
              : _buildGrid(),
    );
  }

  Widget _buildEmpty() {
    return Center(
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
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
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
        final submissionId = data['submissionId'] as String;

        final statusColor = _statusColor(status);
        final statusLabel = _statusLabel(status);

        return GestureDetector(
          onTap: () => Navigator.push(
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
                submissionId: submissionId,
              ),
            ),
          ),
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
