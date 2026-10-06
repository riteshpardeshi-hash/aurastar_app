import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_job_status_badge.dart';

/// One AI video job. What it shows depends on the job's stage: progress while
/// generating or scoring, an image picker once images are ready (images-first
/// step two), and the result with the AI score once scored.
class AiVideoDetailScreen extends StatefulWidget {
  final String jobId;

  const AiVideoDetailScreen({super.key, required this.jobId});

  @override
  State<AiVideoDetailScreen> createState() => _AiVideoDetailScreenState();
}

class _AiVideoDetailScreenState extends State<AiVideoDetailScreen> {
  static const _bg = AppColors.background;
  static const _accent = AppColors.accent;
  static const _card = Color(0xFF0E0E1A);

  final _service = AiAdsService();
  AiVideoJob? _job;
  int? _credits;
  bool _loading = true;
  bool _submitting = false;
  final Set<String> _selected = {};
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
    final job = await _service.fetchJob(widget.jobId);
    final credits =
        job == null ? null : await _service.fetchCredits(job.brandId);
    if (!mounted) return;
    setState(() {
      _job = job;
      _credits = credits;
      _loading = false;
    });
  }

  Future<void> _createVideo() async {
    setState(() => _submitting = true);
    try {
      final job = await _service.startVideoFromImages(
        widget.jobId,
        _selected.toList(),
      );
      if (!mounted) return;
      final credits = await _service.fetchCredits(job.brandId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _credits = credits;
        _selected.clear();
        _submitting = false;
      });
    } on OutOfAiCreditsException {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('You are out of credits');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('Something went wrong. Please try again.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
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
          'AI video',
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
              : _job == null
              ? const Center(
                child: Text(
                  'Video not found',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
              : _buildBody(_job!),
    );
  }

  Widget _buildBody(AiVideoJob job) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AiJobStatusBadge(status: job.status),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Text(
            job.prompt,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 20),
        switch (job.status) {
          AiJobStatus.imagesReady => _imagePicker(job),
          AiJobStatus.scored => _result(job),
          _ => _progress(job),
        },
      ],
    );
  }

  Widget _progress(AiVideoJob job) {
    final msg = switch (job.status) {
      AiJobStatus.generatingImages => 'Generating your images…',
      AiJobStatus.generatingVideo => 'Generating your video…',
      _ => 'Scoring your video against the brand brief…',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const CircularProgressIndicator(color: _accent),
          const SizedBox(height: 16),
          Text(
            msg,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'You can leave this screen. It will be here when you come back.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _imagePicker(AiVideoJob job) {
    final cost = AiAdsService.costs.video;
    final credits = _credits;
    final outOfCredits = credits != null && credits < cost;
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick the images for your video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'ClashDisplay',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select one or more.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [for (final img in job.images) _imageTile(img)],
            ),
            const SizedBox(height: 20),
            if (outOfCredits)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Center(
                  child: Text(
                    'You are out of credits',
                    style: TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed:
                    (_selected.isEmpty || _submitting || outOfCredits)
                        ? null
                        : _createVideo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white54,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child:
                    _submitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Text(
                          'Create video · $cost credits',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
              ),
            ),
          ],
        );
  }

  Widget _imageTile(AiGeneratedImage img) {
    final selected = _selected.contains(img.id);
    return GestureDetector(
      onTap:
          () => setState(() {
            selected ? _selected.remove(img.id) : _selected.add(img.id);
          }),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.url.isNotEmpty)
              Image.network(img.url, fit: BoxFit.cover)
            else
              const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: Colors.white24,
                  size: 36,
                ),
              ),
            if (selected)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.check_circle, color: _accent, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _result(AiVideoJob job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: _cardDecoration(),
            child: const Center(
              child: Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white38,
                size: 56,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${job.score}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      '/ 100 · match with the brand brief',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if ((job.feedback ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  job.feedback!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  );
}
