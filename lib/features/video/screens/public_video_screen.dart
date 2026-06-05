import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../challenges/screens/challenge_detail.dart';
import '../../challenges/screens/category_challenges_screen.dart';
import '../../explore/screens/creator_profile_screen.dart';
import '../../explore/screens/participant_profile_screen.dart';

class PublicVideoScreen extends StatefulWidget {
  final String submissionId;
  final String videoUrl;

  /// 480p optimised URL written by the Cloud Function — used for playback.
  /// Falls back to [videoUrl] when not yet processed.
  final String? videoUrl480p;

  /// Pre-generated thumbnail URL written by the Cloud Function.
  final String? thumbnailUrl;

  final String username;
  final String userId;
  final String challengeTitle;
  final String challengeId;
  final String challengeVideoUrl;
  final int initialStars;
  final bool initiallyStarred;
  final int? auraScore;

  const PublicVideoScreen({
    super.key,
    required this.submissionId,
    required this.videoUrl,
    this.videoUrl480p,
    this.thumbnailUrl,
    required this.username,
    required this.userId,
    required this.challengeTitle,
    required this.challengeId,
    this.challengeVideoUrl = '',
    this.initialStars = 0,
    this.initiallyStarred = false,
    this.auraScore,
  });

  @override
  State<PublicVideoScreen> createState() => _PublicVideoScreenState();
}

class _PublicVideoScreenState extends State<PublicVideoScreen> {
  static const _purple = Color(0xFF7B2CBF);
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Video
  VideoPlayerController? _player;
  bool _playerReady = false;
  bool _isPlaying = false;

  // Stars (local optimistic state)
  late bool _starred;
  late int _stars;
  bool _starLoading = false;

  // Smart link data
  Map<String, dynamic>? _challengeData;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _starred = widget.initiallyStarred;
    _stars = widget.initialStars;
    _initPlayer();
    _fetchChallengeData();
  }

  Future<void> _fetchChallengeData() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('challenges').doc(widget.challengeId).get();
      if (doc.exists && mounted) setState(() => _challengeData = doc.data());
    } catch (_) {}
  }

  Future<void> _initPlayer() async {
    // Prefer 480p optimised version; fall back to original
    final url = (widget.videoUrl480p?.isNotEmpty == true)
        ? widget.videoUrl480p!
        : widget.videoUrl;
    if (url.isEmpty) return;

    _player = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    await _player!.initialize();
    _player!.setLooping(true);
    _player!.play();
    if (mounted) {
      setState(() {
        _playerReady = true;
        _isPlaying = true;
      });
    }
    _player!.addListener(() {
      if (mounted) setState(() => _isPlaying = _player!.value.isPlaying);
    });
  }

  Future<void> _toggleStar() async {
    if (_starLoading) return;
    setState(() {
      _starLoading = true;
      _starred = !_starred;
      _stars += _starred ? 1 : -1;
    });

    final delta = _starred ? 1 : -1;
    final ref = FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId);

    await ref.update({
      'starredBy': _starred
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
      'starsCount': FieldValue.increment(delta),
    });

    if (widget.userId.isNotEmpty && widget.userId != _uid) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'starsReceived': FieldValue.increment(delta)});
    }

    if (mounted) setState(() => _starLoading = false);
  }

  void _togglePlay() {
    if (_player == null) return;
    _isPlaying ? _player!.pause() : _player!.play();
  }

  void _share() {
    Share.share(
        'Watch this challenge on Aura Arena!\n${widget.videoUrl}');
  }

  void _showReport() {
    const reasons = [
      'Bullying / harassment',
      'Unsafe act',
      'Nudity / sexual content',
      'Spam / fake account',
      'Other',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Report Video',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Why are you reporting this?',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 12),
            ...reasons.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white24, size: 18),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('reports')
                        .add({
                      'submissionId': widget.submissionId,
                      'reportedBy': _uid,
                      'reason': r,
                      'createdAt': Timestamp.now(),
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Report submitted. Thank you.')),
                      );
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video (thumbnail shown while buffering) ──────────────────────
          GestureDetector(
            onTap: _togglePlay,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail background — instant load, no video download
                if (widget.thumbnailUrl != null || widget.videoUrl.isNotEmpty)
                  _ThumbnailBackground(
                    videoUrl: widget.videoUrl,
                    thumbnailUrl: widget.thumbnailUrl,
                  ),
                if (_playerReady)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _player!.value.aspectRatio,
                      child: VideoPlayer(_player!),
                    ),
                  ),
                if (!_playerReady)
                  const Center(
                    child: SizedBox(
                      width: 26, height: 26,
                      child: CircularProgressIndicator(
                          color: _purple, strokeWidth: 2.5),
                    ),
                  ),
              ],
            ),
          ),

          // Pause indicator
          if (_playerReady && !_isPlaying)
            const Center(
              child: _PauseIcon(),
            ),

          // ── Top bar ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _iconBtn(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  _iconBtn(Icons.more_vert_rounded, onTap: _showReport),
                ],
              ),
            ),
          ),

          // ── Right sidebar — Star, Share ──────────────────────────────────
          Positioned(
            right: 16,
            bottom: 140,
            child: Column(
              children: [
                _SideAction(
                  icon: _starred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: _starred ? const Color(0xFFFFD700) : Colors.white,
                  label: _formatCount(_stars),
                  loading: _starLoading,
                  onTap: _toggleStar,
                ),
                const SizedBox(height: 24),
                _SideAction(
                  icon: Icons.share_rounded,
                  color: Colors.white,
                  label: 'Share',
                  onTap: _share,
                ),
              ],
            ),
          ),

          // ── Bottom info + CTA ────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.90),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Username
                  GestureDetector(
                    onTap: widget.userId.isNotEmpty
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ParticipantProfileScreen(
                                    userId: widget.userId),
                              ),
                            )
                        : null,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _purple.withValues(alpha: 0.35),
                          child: Text(
                            widget.username.isNotEmpty
                                ? widget.username[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '@${widget.username}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (widget.auraScore != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: _purple.withValues(alpha: 0.60)),
                            ),
                            child: Text(
                              '${widget.auraScore}',
                              style: const TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Challenge title — tappable
                  GestureDetector(
                    onTap: widget.challengeId.isNotEmpty
                        ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChallengeDetail(
                                title: widget.challengeTitle,
                                instructions: '',
                                videoUrl: widget.challengeVideoUrl,
                                challengeId: widget.challengeId,
                              ),
                            ))
                        : null,
                    child: Text(
                      widget.challengeTitle,
                      style: const TextStyle(
                        color: Color(0xFFBB6BD9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  // Smart links row
                  if (_challengeData != null) ...[
                    const SizedBox(height: 8),
                    _buildSmartLinks(),
                  ],

                  const SizedBox(height: 12),

                  // Try Challenge CTA
                  if (widget.challengeId.isNotEmpty)
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChallengeDetail(
                            title: widget.challengeTitle,
                            instructions: '',
                            videoUrl: widget.challengeVideoUrl,
                            challengeId: widget.challengeId,
                          ),
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.40),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Try this Challenge',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartLinks() {
    final cd        = _challengeData!;
    final category  = cd['category']  as String? ?? '';
    final creatorId = cd['creatorId'] as String? ?? '';
    final isSystem  = creatorId == 'system' || creatorId.isEmpty;

    final chips = <Widget>[];

    if (category.isNotEmpty) {
      chips.add(_linkChip(
        label: category,
        icon: Icons.category_outlined,
        color: _categoryColor(category),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => CategoryChallengesScreen(category: category),
        )),
      ));
    }

    if (!isSystem) {
      chips.add(_linkChip(
        label: 'Brand',
        icon: Icons.store_rounded,
        color: const Color(0xFF4B6EF6),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreatorProfileScreen(creatorId: creatorId),
        )),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _linkChip({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'dance':   return const Color(0xFF4B6EF6);
      case 'fitness': return const Color(0xFF22C55E);
      case 'fashion': return const Color(0xFFFF6B9D);
      case 'sports':  return const Color(0xFFF97316);
      case 'comedy':  return const Color(0xFFEAB308);
      case 'skill':   return const Color(0xFF06B6D4);
      default:        return const Color(0xFF7B2CBF);
    }
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

/// Shows a pre-generated thumbnail URL instantly, or falls back to skeleton.
/// Used as the background layer behind the video player while buffering.
class _ThumbnailBackground extends StatelessWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  const _ThumbnailBackground({required this.videoUrl, this.thumbnailUrl});

  @override
  Widget build(BuildContext context) {
    // Import comes from shared widget — this avoids adding another import
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return Image.network(
        thumbnailUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 720,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

class _PauseIcon extends StatelessWidget {
  const _PauseIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child:
            const Icon(Icons.pause_rounded, color: Colors.white, size: 32),
      );
}

class _SideAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _SideAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: loading ? null : onTap,
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: loading
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Icon(icon, key: ValueKey(icon), color: color, size: 32),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
