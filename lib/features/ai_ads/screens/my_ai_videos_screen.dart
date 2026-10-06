import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_job_status_badge.dart';
import 'ai_video_detail_screen.dart';

/// The creator's AI video jobs for one brand: in progress, waiting on image
/// picks, or scored. Generation is asynchronous, so this is where creators
/// come back to.
class MyAiVideosScreen extends StatefulWidget {
  final String brandId;

  const MyAiVideosScreen({super.key, required this.brandId});

  @override
  State<MyAiVideosScreen> createState() => _MyAiVideosScreenState();
}

class _MyAiVideosScreenState extends State<MyAiVideosScreen> {
  static const _bg = AppColors.background;
  static const _accent = AppColors.accent;
  static const _card = Color(0xFF0E0E1A);

  final _service = AiAdsService();
  List<AiVideoJob> _jobs = [];
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final jobs = await _service.fetchJobs(widget.brandId);
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _loading = false;
    });
  }

  Future<void> _open(AiVideoJob job) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AiVideoDetailScreen(jobId: job.id)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'My AI videos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'ClashDisplay',
          ),
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : _jobs.isEmpty
              ? const Center(
                child: Text(
                  'No AI videos yet',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: _jobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _jobCard(_jobs[i]),
              ),
    );
  }

  Widget _jobCard(AiVideoJob job) {
    return GestureDetector(
      onTap: () => _open(job),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AiJobStatusBadge(status: job.status),
                  const SizedBox(height: 8),
                  Text(
                    job.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (job.score != null)
              Column(
                children: [
                  Text(
                    '${job.score}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const Text(
                    'score',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              )
            else if (job.isInProgress)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
