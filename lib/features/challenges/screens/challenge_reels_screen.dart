import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/aura_score_badge.dart';
import '../../../shared/widgets/category_icon_badge.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import 'challenge_detail.dart';

/// Full-screen vertical video feed opened from the bottom nav's center
/// star button — for every role (player, creator, brand, admin alike).
/// Autoplays each challenge's reference video; when one finishes it
/// auto-advances to the next, the user can also swipe manually, and the
/// feed loops forever (wraps back to page 1 once the backend runs out of
/// pages, same pattern as AllGeneralChallengesScreen's grid). Tapping the
/// video opens its ChallengeDetail page. The only chrome is a bottom
/// overlay with the category icon, aura points, and participant count.
class ChallengeReelsScreen extends StatefulWidget {
  const ChallengeReelsScreen({super.key});

  @override
  State<ChallengeReelsScreen> createState() => _ChallengeReelsScreenState();
}

class _ChallengeReelsScreenState extends State<ChallengeReelsScreen> {
  static const _accent = Color(0xFF7B2CBF);
  static const _pageSize = 20;

  final _pageController = PageController();
  final List<Map<String, dynamic>> _reels = [];
  int _currentIndex = 0;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;

  // categoryId → name, for resolving each reel's category icon badge.
  Map<String, String> _categoryNames = const {};

  @override
  void initState() {
    super.initState();
    _loadInitial();
    ChallengesService().fetchCategoryNameMap().then((map) {
      if (mounted) setState(() => _categoryNames = map);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    try {
      final raw =
          await ChallengesService().fetchChallenges(page: 1, limit: _pageSize);
      final list = raw
          .map(normaliseChallenge)
          .where((c) => (c['videoUrl'] as String).isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _reels.addAll(list);
        _hasMore = list.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Once the backend runs out of pages the next load wraps back to page 1
  // instead of stopping, so the feed never dead-ends.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final nextPage = _hasMore ? _page + 1 : 1;
      final raw = await ChallengesService()
          .fetchChallenges(page: nextPage, limit: _pageSize);
      final list = raw
          .map(normaliseChallenge)
          .where((c) => (c['videoUrl'] as String).isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _reels.addAll(list);
        _hasMore = list.length == _pageSize;
      });
    } catch (_) {
      // keep whatever's already loaded — the next scroll-near-end retries
    } finally {
      _loadingMore = false;
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    if (index >= _reels.length - 3) _loadMore();
  }

  void _goToNext() {
    if (!_pageController.hasClients) return;
    final next = _currentIndex + 1;
    if (next < _reels.length) {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openDetail(Map<String, dynamic> c) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeDetail(
          title: c['title'] as String,
          instructions: c['instructions'] as String,
          videoUrl: c['videoUrl'] as String,
          challengeId: c['id'] as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent),
            )
          : _reels.isEmpty
              ? const Center(
                  child: Text(
                    'No challenges yet',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      itemCount: _reels.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        final c = _reels[index];
                        return _ReelPage(
                          key: ValueKey('${c['id']}_$index'),
                          videoUrl: c['videoUrl'] as String,
                          thumbnailUrl: c['thumbnailUrl'] as String? ?? '',
                          categoryName: _categoryNames[c['category'] as String? ?? ''],
                          participants: c['submissionsCount'] as int,
                          isActive: index == _currentIndex,
                          onTap: () => _openDetail(c),
                          onEnd: _goToNext,
                        );
                      },
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 6,
                      left: 6,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final String videoUrl;
  final String thumbnailUrl;
  final String? categoryName;
  final int participants;
  final bool isActive;
  final Future<void> Function() onTap;
  final VoidCallback onEnd;

  const _ReelPage({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.categoryName,
    required this.participants,
    required this.isActive,
    required this.onTap,
    required this.onEnd,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  static const _accent = Color(0xFF7B2CBF);

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _ctrl = ctrl;
    ctrl.addListener(_onTick);
    await ctrl.initialize();
    if (!mounted) return;
    setState(() => _ready = true);
    if (widget.isActive) ctrl.play();
  }

  // Fires once as playback nears the very end of the clip, regardless of
  // whether the platform player has already flipped `isPlaying` to false by
  // that point (observed to vary), so the auto-advance is reliable either way.
  void _onTick() {
    final ctrl = _ctrl;
    if (ctrl == null || _ended) return;
    final v = ctrl.value;
    if (!v.isInitialized || v.duration <= Duration.zero) return;
    if (v.position >= v.duration - const Duration(milliseconds: 150)) {
      _ended = true;
      widget.onEnd();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    final ctrl = _ctrl;
    if (ctrl == null || !_ready || widget.isActive == old.isActive) return;
    if (widget.isActive) {
      _ended = false;
      ctrl.seekTo(Duration.zero).then((_) => ctrl.play());
    } else {
      ctrl.pause();
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  // Pause before navigating to ChallengeDetail — this page stays mounted
  // (just covered) underneath the pushed route, and without pausing here
  // its audio kept playing on top of ChallengeDetail's own video. Resume
  // only if this reel is still the active one once the user comes back.
  Future<void> _handleTap() async {
    _ctrl?.pause();
    await widget.onTap();
    if (mounted && widget.isActive) _ctrl?.play();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final aspect = ctrl != null && ctrl.value.isInitialized
        ? correctedVideoAspectRatio(ctrl.value)
        : 9 / 16;
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnailWidget(
              videoUrl: widget.videoUrl,
              thumbnailUrl:
                  widget.thumbnailUrl.isNotEmpty ? widget.thumbnailUrl : null,
              fit: BoxFit.cover,
            ),
            if (_ready && ctrl != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 1000,
                  height: 1000 / aspect,
                  child: VideoPlayer(ctrl),
                ),
              ),
            if (!_ready)
              const Center(
                child: CircularProgressIndicator(color: _accent),
              ),
            // Bottom gradient + overlay — category icon, aura points, participants.
            IgnorePointer(
              child: Container(
                alignment: Alignment.bottomCenter,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.75, 1.0],
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                child: Row(
                  children: [
                    CategoryIconBadge(categoryName: widget.categoryName, size: 24),
                    const SizedBox(width: 10),
                    const AuraScoreBadge(),
                    const SizedBox(width: 12),
                    const Icon(Icons.groups_rounded,
                        color: Colors.white60, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(widget.participants),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
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
