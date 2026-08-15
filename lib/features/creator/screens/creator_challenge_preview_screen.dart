import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../video/widgets/video_player_widget.dart';

/// Renders a challenge exactly as players will see it after publish —
/// `GET /creator/challenges/{id}/preview` — so a creator can check their
/// work before hitting Submit. Distinct from the draft-editing screens,
/// which show raw form fields rather than the player-facing presentation.
class CreatorChallengePreviewScreen extends StatefulWidget {
  final String challengeId;

  const CreatorChallengePreviewScreen({super.key, required this.challengeId});

  @override
  State<CreatorChallengePreviewScreen> createState() =>
      _CreatorChallengePreviewScreenState();
}

class _CreatorChallengePreviewScreenState
    extends State<CreatorChallengePreviewScreen> {
  static const _bg = Color(0xFF080810);
  static const _card = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  Map<String, dynamic>? _preview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await CreatorChallengesService().fetchPreview(widget.challengeId);
    if (!mounted) return;
    setState(() {
      _preview = raw;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Preview',
            style: TextStyle(fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _preview == null
              ? const Center(
                  child: Text('Preview unavailable',
                      style: TextStyle(color: AppColors.textMuted)))
              : _buildBody(_preview!),
    );
  }

  Widget _buildBody(Map<String, dynamic> preview) {
    final title = preview['title'] as String? ?? '';
    final description = preview['description'] as String? ?? '';
    final difficulty = preview['difficulty'] as String? ?? '';
    final videoUrl = preview['videoUrl'] as String? ?? '';
    final thumbnailUrl = preview['thumbnailUrl'] as String?;
    final status = preview['submissionStatus'] as String?;
    final category = preview['category'];
    final categoryName = category is Map
        ? (category['name'] as String? ?? '')
        : (category as String? ?? '');
    final instructions = preview['challengeInstructions'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (videoUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: VideoPlayerWidget(videoUrl, thumbnailUrl: thumbnailUrl),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay'),
              ),
            ),
            if (status != null) _statusBadge(status),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (categoryName.isNotEmpty) _tag(Icons.category_outlined, categoryName),
            if (categoryName.isNotEmpty && difficulty.isNotEmpty) const SizedBox(width: 8),
            if (difficulty.isNotEmpty) _tag(Icons.speed_rounded, difficulty),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(description,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
        ],
        if (instructions != null) ...[
          const SizedBox(height: 20),
          const Text('Instructions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 10),
          if ((instructions['whatToCopy'] as String?)?.isNotEmpty == true)
            _instructionRow('What to copy', instructions['whatToCopy'] as String),
          if (instructions['timeLimit'] != null)
            _instructionRow(
                'Time limit', '${instructions['timeLimit']}s'),
          if ((instructions['allowedProps'] as List?)?.isNotEmpty == true)
            _instructionList('Allowed props',
                (instructions['allowedProps'] as List).cast<String>()),
          if ((instructions['safetyNotes'] as List?)?.isNotEmpty == true)
            _instructionList('Safety notes',
                (instructions['safetyNotes'] as List).cast<String>()),
          if ((instructions['scoringCriteria'] as List?)?.isNotEmpty == true)
            _instructionList('Scoring criteria',
                (instructions['scoringCriteria'] as List).cast<String>()),
        ],
      ],
    );
  }

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Text(status,
          style: const TextStyle(
              color: Color(0xFFD4A8FF), fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _tag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _instructionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _instructionList(String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
