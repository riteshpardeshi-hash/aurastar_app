import 'package:flutter/material.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../challenges/screens/challenge_detail.dart';

class SavedChallengesScreen extends StatefulWidget {
  const SavedChallengesScreen({super.key});

  @override
  State<SavedChallengesScreen> createState() => _SavedChallengesScreenState();
}

class _SavedChallengesScreenState extends State<SavedChallengesScreen> {
  static const _bg     = Color(0xFF0D0D1A);
  static const _card   = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  List<Map<String, dynamic>> _challenges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await AuthApiService().fetchSavedChallenges(limit: 50);
    if (mounted) {
      setState(() {
        _challenges = data.map(normaliseChallenge).toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Saved Challenges',
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
          : _challenges.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: _challenges.length,
      itemBuilder: (_, i) => _buildCard(_challenges[i]),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final id           = c['id']           as String? ?? '';
    final title        = c['title']        as String? ?? 'Challenge';
    final videoUrl     = c['videoUrl']     as String? ?? '';
    final thumbnailUrl = c['thumbnailUrl'] as String? ?? '';
    final instructions = c['instructions'] as String? ?? '';
    final category     = c['category']     as String? ?? '';
    final difficulty   = c['difficulty']   as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          // Thumbnail
          GestureDetector(
            onTap: () => _openDetail(id, title, instructions, videoUrl),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 90,
                height: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnailWidget(
                        videoUrl: videoUrl,
                        thumbnailUrl: thumbnailUrl,
                        fit: BoxFit.cover),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5)
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.3)),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (category.isNotEmpty) _chip(category, _accent),
                      if (difficulty.isNotEmpty)
                        _chip(difficulty, _difficultyColor(difficulty)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Take button
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => _openDetail(id, title, instructions, videoUrl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Take',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(
      String id, String title, String instructions, String videoUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeDetail(
          title: title,
          instructions: instructions,
          videoUrl: videoUrl,
          challengeId: id,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_outline_rounded,
                color: Colors.white.withValues(alpha: 0.15), size: 64),
            const SizedBox(height: 20),
            const Text('No saved challenges',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text(
              'Tap the bookmark icon on any challenge\nto save it for later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white30, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':   return Colors.green;
      case 'medium': return Colors.orange;
      case 'hard':   return Colors.deepOrange;
      default:       return Colors.white54;
    }
  }
}
