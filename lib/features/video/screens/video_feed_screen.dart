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
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../core/services/video_cache_service.dart';

/// Vertical TikTok-style video feed.
/// Each item in [submissions] must be: `{'id': String, 'data': Map}`
class VideoFeedScreen extends StatefulWidget {
  final List<Map<String, dynamic>> submissions;
  final int initialIndex;

  const VideoFeedScreen({
    super.key,
    required this.submissions,
    required this.initialIndex,
  });

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: widget.submissions.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) {
          final item = widget.submissions[i];
          return _VideoPage(
            key: ValueKey(item['id'] as String),
            submissionId: item['id'] as String,
            data: item['data'] as Map<String, dynamic>,
            isActive: i == _currentIndex,
            isPreload: i == _currentIndex + 1,
          );
        },
      ),
    );
  }
}

// ── Single video page ─────────────────────────────────────────────────────────

class _VideoPage extends StatefulWidget {
  final String submissionId;
  final Map<String, dynamic> data;
  final bool isActive;
  final bool isPreload;

  const _VideoPage({
    super.key,
    required this.submissionId,
    required this.data,
    required this.isActive,
    this.isPreload = false,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  static const _purple = Color(0xFF7B2CBF);
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  VideoPlayerController? _player;
  bool _playerReady = false;
  bool _initStarted = false;
  bool _isPlaying = false;

  late bool _starred;
  late int _stars;
  bool _starLoading = false;

  // Smart link data fetched lazily from the challenge doc
  Map<String, dynamic>? _challengeData;
  bool _challengeFetched = false;

  @override
  void initState() {
    super.initState();
    final starredBy = (widget.data['starredBy'] as List?) ?? [];
    _starred = starredBy.contains(_uid);
    _stars = (widget.data['starsCount'] as num?)?.toInt() ?? 0;
    if (widget.isActive || widget.isPreload) _initPlayer();
    if (widget.isActive) _fetchChallengeData();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);

    if (!old.isActive && widget.isActive) {
      _fetchChallengeData();
      if (_playerReady) {
        _player?.play();
        setState(() => _isPlaying = true);
      } else if (!_initStarted) {
        _initPlayer();
      }
      // If init is in-flight, _initPlayer will auto-play once ready
    } else if (old.isActive && !widget.isActive) {
      _player?.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else if (!old.isPreload && widget.isPreload && !_initStarted) {
      _initPlayer(); // newly entered preload range
    }
  }

  Future<void> _initPlayer() async {
    if (_initStarted) return;
    _initStarted = true;

    final videoUrl = widget.data['videoUrl'] as String? ?? '';
    // Prefer 480p optimised version produced by the Cloud Function
    final playUrl = (widget.data['videoUrl480p'] as String?)?.isNotEmpty == true
        ? widget.data['videoUrl480p'] as String
        : videoUrl;
    if (playUrl.isEmpty) return;

    VideoCacheService.markViewed(playUrl);

    _player = VideoPlayerController.networkUrl(
      Uri.parse(playUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    await _player!.initialize();
    _player!.setLooping(true);

    if (widget.isActive) _player!.play();

    if (mounted) {
      setState(() {
        _playerReady = true;
        _isPlaying = widget.isActive;
      });
    }

    _player!.addListener(() {
      if (mounted) setState(() => _isPlaying = _player!.value.isPlaying);
    });
  }

  Future<void> _fetchChallengeData() async {
    if (_challengeFetched) return;
    _challengeFetched = true;
    final cid = widget.data['challengeId'] as String? ?? '';
    if (cid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('challenges').doc(cid).get();
      if (doc.exists && mounted) setState(() => _challengeData = doc.data());
    } catch (_) {}
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_player == null) return;
    _isPlaying ? _player!.pause() : _player!.play();
  }

  Future<void> _toggleStar() async {
    if (_starLoading) return;
    final userId = widget.data['userId'] as String? ?? '';
    setState(() { _starLoading = true; _starred = !_starred; _stars += _starred ? 1 : -1; });

    final delta = _starred ? 1 : -1;
    await FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId)
        .update({
      'starredBy': _starred
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
      'starsCount': FieldValue.increment(delta),
    });
    if (userId.isNotEmpty && userId != _uid) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'starsReceived': FieldValue.increment(delta)});
    }
    if (mounted) setState(() => _starLoading = false);
  }

  void _showReport(BuildContext context) {
    const reasons = [
      'Bullying / harassment', 'Unsafe act', 'Nudity / sexual content',
      'Spam / fake account', 'Other',
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
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            const Text('Report Video',
                style: TextStyle(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Why are you reporting this?',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 12),
            ...reasons.map((r) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(r,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Colors.white24, size: 18),
              onTap: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance.collection('reports').add({
                  'submissionId': widget.submissionId,
                  'reportedBy': _uid,
                  'reason': r,
                  'createdAt': Timestamp.now(),
                });
                if (context.mounted) {
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
  Widget build(BuildContext context) {
    final username = widget.data['username'] as String? ?? 'User';
    final userId = widget.data['userId'] as String? ?? '';
    final challengeTitle =
        widget.data['challengeTitle'] as String? ?? 'Challenge';
    final challengeId = widget.data['challengeId'] as String? ?? '';
    final videoUrl = widget.data['videoUrl'] as String? ?? '';
    final thumbnailUrl = widget.data['thumbnailUrl'] as String?;
    final aiScore = (widget.data['aiScore'] as num?)?.toInt();

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail shown until video is ready
          VideoThumbnailWidget(
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            fit: BoxFit.cover,
          ),

          // Video overlaid once initialised
          if (_playerReady)
            Center(
              child: AspectRatio(
                aspectRatio: _player!.value.aspectRatio,
                child: VideoPlayer(_player!),
              ),
            ),

          // Buffering indicator
          if (!_playerReady && widget.isActive)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: _purple, strokeWidth: 2.5),
              ),
            ),

          if (_playerReady && !_isPlaying)
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pause_rounded,
                    color: Colors.white, size: 32),
              ),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _iconBtn(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  _iconBtn(Icons.more_vert_rounded,
                      onTap: () => _showReport(context)),
                ],
              ),
            ),
          ),

          // Right sidebar
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
                  label: _fmt(_stars),
                  loading: _starLoading,
                  onTap: _toggleStar,
                ),
                const SizedBox(height: 24),
                _SideAction(
                  icon: Icons.share_rounded,
                  color: Colors.white,
                  label: 'Share',
                  onTap: () => Share.share(
                      'Watch this challenge on Aura Arena!\n$videoUrl'),
                ),
              ],
            ),
          ),

          // Bottom info
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
                    Colors.transparent
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 40, 90, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: userId.isNotEmpty
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ParticipantProfileScreen(userId: userId),
                              ),
                            )
                        : null,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: _purple.withValues(alpha: 0.35),
                          child: Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('@$username',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        if (aiScore != null) ...[
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
                            child: Text('$aiScore',
                                style: const TextStyle(
                                    color: Color(0xFFD4A8FF),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Challenge title — tappable
                  GestureDetector(
                    onTap: challengeId.isNotEmpty
                        ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChallengeDetail(
                                title: challengeTitle,
                                instructions: '',
                                videoUrl: videoUrl,
                                challengeId: challengeId,
                              ),
                            ))
                        : null,
                    child: Text(challengeTitle,
                        style: const TextStyle(
                            color: Color(0xFFBB6BD9),
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                  // Smart links row
                  if (_challengeData != null) ...[
                    const SizedBox(height: 8),
                    _buildSmartLinks(context, challengeTitle, challengeId, videoUrl),
                  ],
                  if (challengeId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChallengeDetail(
                            title: challengeTitle,
                            instructions: '',
                            videoUrl: videoUrl,
                            challengeId: challengeId,
                          ),
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.40),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            )
                          ],
                        ),
                        child: const Center(
                          child: Text('Try this Challenge',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartLinks(BuildContext context, String challengeTitle, String challengeId, String videoUrl) {
    final cd         = _challengeData!;
    final category   = cd['category']   as String? ?? '';
    final creatorId  = cd['creatorId']  as String? ?? '';
    final isSystem   = creatorId == 'system' || creatorId.isEmpty;

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
              shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';
}

// ── Reusable side action button ───────────────────────────────────────────────

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
