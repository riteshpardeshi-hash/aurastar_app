import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../../core/utils/cdn_url.dart';
import '../widgets/achievement_card.dart';
import '../widgets/challenge_offer_banner.dart';
import '../../video/screens/preview_screen.dart';
import 'camera_screen.dart';

class ChallengeDetail extends StatefulWidget {
  final String title;
  final String instructions;
  final String videoUrl;
  final String challengeId;

  const ChallengeDetail({
    super.key,
    required this.title,
    required this.instructions,
    required this.videoUrl,
    required this.challengeId,
  });

  @override
  State<ChallengeDetail> createState() => _ChallengeDetailState();
}

class _ChallengeDetailState extends State<ChallengeDetail> {
  static const _bg = Color(0xFF0D0D1A);
  static const _accent = Color(0xFF7B2CBF);

  // Video state
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoStarted = false; // true once user taps play
  bool _isPlaying = false;
  bool _isFullscreen = false;

  // Challenge data
  int _auraPoints = 150;
  String _difficulty = '';
  String _sourceType = '';
  String _category = '';
  dynamic _endDate;
  bool _isPaused = false;

  // Stats
  int _attemptCount = 0;
  int _topScore = 0;
  bool _statsLoaded = false;

  // Bookmark
  bool _isSaved = false;
  bool _savingBookmark = false;

  // Like
  bool _liked = false;
  int _likesCount = 0;
  bool _likingBusy = false;

  void _onVideoUpdate() {
    if (mounted) setState(() => _isPlaying = _videoController!.value.isPlaying);
  }

  @override
  void initState() {
    super.initState();
    _fetchChallengeData();
    _fetchStats();
    _checkSaved();
  }

  Future<void> _fetchChallengeData() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('challenges')
          .doc(widget.challengeId)
          .get();
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final likedBy = List<String>.from(data['likedBy'] ?? []);
      setState(() {
        _auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 150;
        _difficulty = data['difficulty'] as String? ?? '';
        _sourceType = data['sourceType'] as String? ?? '';
        _category = data['category'] as String? ?? '';
        _endDate = data['endDate'];
        _isPaused = (data['status'] as String? ?? '') == 'paused';
        _likesCount = (data['likesCount'] as num?)?.toInt() ?? likedBy.length;
        _liked = uid.isNotEmpty && likedBy.contains(uid);
      });
    } catch (_) {}
  }

  Future<void> _checkSaved() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.challengeId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('saved_challenges').doc(widget.challengeId)
          .get();
      if (mounted) setState(() => _isSaved = doc.exists);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.challengeId.isEmpty || _savingBookmark) return;
    setState(() => _savingBookmark = true);
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('saved_challenges').doc(widget.challengeId);
    try {
      if (_isSaved) {
        await ref.delete();
        if (mounted) setState(() { _isSaved = false; _savingBookmark = false; });
      } else {
        await ref.set({
          'challengeId':   widget.challengeId,
          'title':         widget.title,
          'instructions':  widget.instructions,
          'videoUrl':      widget.videoUrl,
          'auraPoints':    _auraPoints,
          'category':      _category,
          'difficulty':    _difficulty,
          'savedAt':       FieldValue.serverTimestamp(),
        });
        if (mounted) setState(() { _isSaved = true; _savingBookmark = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _savingBookmark = false);
    }
  }

  Future<void> _toggleLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.challengeId.isEmpty || _likingBusy) return;
    setState(() => _likingBusy = true);
    final ref = FirebaseFirestore.instance
        .collection('challenges')
        .doc(widget.challengeId);
    final wasLiked = _liked;
    try {
      await ref.update({
        'likedBy': wasLiked
            ? FieldValue.arrayRemove([uid])
            : FieldValue.arrayUnion([uid]),
        'likesCount': FieldValue.increment(wasLiked ? -1 : 1),
      });
      if (mounted) {
        setState(() {
          _liked = !wasLiked;
          _likesCount += wasLiked ? -1 : 1;
          _likingBusy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _likingBusy = false);
    }
  }

  Future<void> _fetchStats() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final countSnap = await FirebaseFirestore.instance
          .collection('submissions')
          .where('challengeId', isEqualTo: widget.challengeId)
          .where('status', isEqualTo: 'approved')
          .count()
          .get();
      final topSnap = await FirebaseFirestore.instance
          .collection('submissions')
          .where('challengeId', isEqualTo: widget.challengeId)
          .where('status', isEqualTo: 'approved')
          .orderBy('aiScore', descending: true)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        _attemptCount = countSnap.count ?? 0;
        if (topSnap.docs.isNotEmpty) {
          final d = topSnap.docs.first.data();
          _topScore = (d['aiScore'] as num?)?.toInt() ?? 0;
        }
        _statsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  Future<void> _initAndPlayVideo() async {
    if (_videoStarted) {
      // Toggle play/pause
      if (_videoController?.value.isPlaying == true) {
        _videoController!.pause();
        setState(() => _isPlaying = false);
      } else {
        _videoController!.play();
        setState(() => _isPlaying = true);
      }
      return;
    }

    setState(() => _videoStarted = true);

    if (widget.videoUrl.isEmpty) return;
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    await _videoController!.initialize();
    if (!mounted) return;
    _videoController!.addListener(_onVideoUpdate);
    setState(() => _videoInitialized = true);
    _videoController!.play();
    setState(() => _isPlaying = true);
  }

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _share() {
    final link = '$kChallengeBaseUrl/${widget.challengeId}';
    Share.share(
      'Check out this challenge on Aura: "${widget.title}" 🌟\n\n'
      'Think you can complete it? 💪\n\n'
      '👉 $link',
    );
  }

  void _showCameraRulesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CameraRulesSheet(
        onConfirm: () {
          Navigator.of(ctx).pop();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraScreen(
                challengeTitle: widget.title,
                challengeId: widget.challengeId,
                referenceVideoUrl: widget.videoUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReportSheet(
        challengeId: widget.challengeId,
        challengeTitle: widget.title,
      ),
    );
  }

  void _showTakeChallengeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12102A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'How do you want to submit?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _sheetOption(
              icon: Icons.videocam_rounded,
              label: 'Record Now',
              subtitle: 'Use your camera to record',
              onTap: () {
                Navigator.pop(context);
                _showCameraRulesModal();
              },
            ),
            const SizedBox(height: 10),
            _sheetOption(
              icon: Icons.photo_library_outlined,
              label: 'Pick from Gallery',
              subtitle: 'Choose an existing video',
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                final picked = await ImagePicker()
                    .pickVideo(source: ImageSource.gallery);
                if (picked == null) return;
                if (!mounted) return;
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => PreviewScreen(
                      videoPath: picked.path,
                      challengeTitle: widget.title,
                      challengeId: widget.challengeId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // ── Main scrollable content ──────────────────────────────────
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top safe area padding for back button
                        SizedBox(
                            height: MediaQuery.of(context).padding.top + 52),

                        // Title
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 6),
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                        ),

                        // Subtitle (first line of instructions, purple)
                        if (_subtitle.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Text(
                              _subtitle,
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                              ),
                            ),
                          ),

                        // Meta chips: source • category • difficulty • aura
                        _buildMetaRow(),

                        // Video player
                        _buildVideoSection(),

                        // Stats bar: attempts + top score
                        _buildStatsBar(),

                        // Details section
                        _buildDetailsSection(),

                        // Scoring rubric
                        _buildScoringRubric(),

                        // Rules section
                        _buildRulesSection(),

                        // Rewards section
                        _buildRewardsSection(),

                        // Brand offer unlock
                        if (widget.challengeId.isNotEmpty)
                          ChallengeOfferBanner(
                              challengeId: widget.challengeId),

                        // Leaderboard
                        if (widget.challengeId.isNotEmpty)
                          _ChallengeLeaderboard(
                              challengeId: widget.challengeId),

                        // Space for sticky button
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Back button overlay ──────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _share,
                    icon: const Icon(Icons.share_rounded,
                        color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _savingBookmark ? null : _toggleSave,
                    icon: _savingBookmark
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(
                            _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                            color: _isSaved ? const Color(0xFFD4A8FF) : Colors.white,
                            size: 20,
                          ),
                    style: IconButton.styleFrom(
                      backgroundColor: _isSaved
                          ? const Color(0xFF7B2CBF).withValues(alpha: 0.30)
                          : Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _LikeButton(
                    liked: _liked,
                    count: _likesCount,
                    busy: _likingBusy,
                    onTap: _toggleLike,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _showReportSheet,
                    icon: const Icon(Icons.flag_outlined,
                        color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // ── Sticky bottom button ────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _bg.withValues(alpha: 0),
                      _bg.withValues(alpha: 0.95),
                      _bg,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Take this Challenge / Paused state
                    Expanded(
                      child: _isPaused
                          ? Container(
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.amber.withValues(alpha: 0.40),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.pause_circle_outline_rounded,
                                      color: Colors.amber.withValues(alpha: 0.80),
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Submissions Paused',
                                    style: TextStyle(
                                      color: Colors.amber.withValues(alpha: 0.80),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: _showTakeChallengeSheet,
                              child: Container(
                                height: 58,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accent.withValues(alpha: 0.50),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'Take this Challenge',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Fullscreen overlay ──────────────────────────────────────
            if (_isFullscreen)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_videoController?.value.isPlaying == true) {
                            _videoController!.pause();
                          } else {
                            _videoController?.play();
                          }
                          setState(() {});
                        },
                        child: Center(
                          child: _videoInitialized
                              ? AspectRatio(
                                  aspectRatio:
                                      _videoController!.value.aspectRatio,
                                  child: VideoPlayer(_videoController!),
                                )
                              : const CircularProgressIndicator(
                                  color: _accent),
                        ),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                            onPressed: _exitFullscreen,
                          ),
                        ),
                      ),
                      if (_videoInitialized &&
                          !_videoController!.value.isPlaying)
                        Center(
                          child: IgnorePointer(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 36),
                            ),
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

  // ── Meta row ──────────────────────────────────────────────────────────────
  Widget _buildMetaRow() {
    final chips = <Widget>[];
    if (_sourceType.isNotEmpty) {
      chips.add(_metaChip(_sourceType, Icons.verified_outlined, _sourceTypeColor));
    }
    if (_category.isNotEmpty) {
      chips.add(_metaChip(_category, Icons.category_outlined, Colors.white54));
    }
    if (_difficulty.isNotEmpty) {
      chips.add(_metaChip(_difficulty, Icons.speed_outlined, _difficultyColor));
    }
    chips.add(_metaChip('$_auraPoints Aura', Icons.diamond, _accent));
    final endLabel = campaignEndLabel(_endDate);
    if (endLabel.isNotEmpty) {
      chips.add(_metaChip(
          endLabel, Icons.timer_outlined, campaignEndColor(_endDate)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }

  Widget _metaChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────────────────────
  Widget _buildStatsBar() {
    if (!_statsLoaded || (_attemptCount == 0 && _topScore == 0 && _likesCount == 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _statItem(Icons.people_outline_rounded, _formatCount(_attemptCount), 'Attempts'),
            Container(width: 1, height: 32, color: Colors.white12),
            _statItem(Icons.emoji_events_outlined, _topScore > 0 ? '$_topScore' : '—', 'Top Score'),
            Container(width: 1, height: 32, color: Colors.white12),
            _statItem(
              _liked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
              _formatCount(_likesCount),
              'Likes',
              color: _liked ? Colors.pinkAccent : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, {Color? color}) {
    final c = color ?? _accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 15),
            const SizedBox(width: 5),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  // ── Scoring rubric ────────────────────────────────────────────────────────
  Widget _buildScoringRubric() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scoring :',
            style: TextStyle(color: _accent, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _scorePill('Style', '30%', const Color(0xFF4B6EF6)),
              _scorePill('Match', '30%', const Color(0xFF9B4DCA)),
              _scorePill('Confidence', '20%', const Color(0xFFFF6B9D)),
              _scorePill('Finish', '20%', const Color(0xFF06B6D4)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scorePill(String label, String pct, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            TextSpan(text: '  $pct', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ── Video section ──────────────────────────────────────────────────────────
  Widget _buildVideoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: GestureDetector(
        onTap: _initAndPlayVideo,
        onLongPress: _videoInitialized ? _enterFullscreen : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background / thumbnail
                if (!_videoStarted || !_videoInitialized)
                  VideoThumbnailWidget(
                      videoUrl: widget.videoUrl, fit: BoxFit.cover)
                else
                  VideoPlayer(_videoController!),

                // Loading spinner
                if (_videoStarted && !_videoInitialized)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  ),

                // Play/pause overlay
                if (!_isPlaying)
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.90),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.55),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ),

                // Fullscreen button
                if (_videoInitialized)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: GestureDetector(
                      onTap: _enterFullscreen,
                      child: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white60, size: 22),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Details section ────────────────────────────────────────────────────────
  Widget _buildDetailsSection() {
    final bullets = _bulletPoints;
    if (bullets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Details :',
            style: TextStyle(
              color: _accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(
                          color: Colors.white, fontSize: 15, height: 1.5)),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.5),
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

  // ── Rules section ─────────────────────────────────────────────────────────
  Widget _buildRulesSection() {
    const rules = [
      (
        icon: Icons.auto_awesome_rounded,
        color: Color(0xFF9B4DCA),
        text: 'AuraSense scores you — no human judges, no bias.',
      ),
      (
        icon: Icons.content_copy_rounded,
        color: Color(0xFF54A0FF),
        text: 'Match the timing, movements and sound as closely as you can.',
      ),
      (
        icon: Icons.shield_outlined,
        color: Color(0xFF22C55E),
        text: 'Fair play only — duplicates and unsafe content will be penalised.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rules :',
            style: TextStyle(
              color: _accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: rules.map((r) {
                final isLast = r == rules.last;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: r.color.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(r.icon, color: r.color, size: 15),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            r.text,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rewards section ────────────────────────────────────────────────────────
  Widget _buildRewardsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rewards :',
            style: TextStyle(
              color: _accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.diamond, color: _accent, size: 44),
              const SizedBox(width: 8),
              Text(
                '$_auraPoints',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String get _subtitle {
    final text = widget.instructions.trim();
    if (text.isEmpty) return '';
    final firstLine = text.split('\n').first.trim();
    // Use first line only if it's reasonably short (tagline-like)
    if (firstLine.length <= 80 &&
        widget.instructions.contains('\n')) {
      return firstLine;
    }
    return '';
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }

  Color get _difficultyColor {
    switch (_difficulty.toLowerCase()) {
      case 'easy': return Colors.greenAccent;
      case 'medium': return Colors.yellow;
      case 'hard': return Colors.orange;
      case 'pro': return Colors.redAccent;
      default: return Colors.white54;
    }
  }

  Color get _sourceTypeColor {
    switch (_sourceType.toLowerCase()) {
      case 'brand': return const Color(0xFF4B6EF6);
      case 'creator': return const Color(0xFFFF6B9D);
      case 'sponsored': return const Color(0xFFFFD700);
      default: return _accent;
    }
  }

  List<String> get _bulletPoints {
    final text = widget.instructions.trim();
    if (text.isEmpty) return [];

    // If multi-line, split by newlines
    if (text.contains('\n')) {
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      // Skip first line if it was used as subtitle
      return _subtitle.isNotEmpty ? lines.skip(1).toList() : lines;
    }

    // Single paragraph — split into sentences
    final sentences = text
        .split('. ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s.endsWith('.') ? s : '$s.')
        .toList();
    return sentences.length > 1 ? sentences : [text];
  }
}

// ── Per-challenge leaderboard ──────────────────────────────────────────────────
class _ChallengeLeaderboard extends StatelessWidget {
  final String challengeId;
  const _ChallengeLeaderboard({required this.challengeId});

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('challengeId', isEqualTo: challengeId)
          .where('status', isEqualTo: 'approved')
          .orderBy('aiScore', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top Scores',
                style: TextStyle(
                  color: Color(0xFF7B2CBF),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              ...List.generate(docs.length, (i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final username = data['username'] as String? ?? 'User';
                final score = (data['aiScore'] as num?)?.toInt() ?? 0;
                final isTop = i == 0;

                final submissionId = docs[i].id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isTop
                        ? _accent.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isTop
                          ? _accent.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(_medal(i),
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isTop
                                ? FontWeight.bold
                                : FontWeight.w400,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Icon(Icons.diamond,
                          color: _accent, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        '$score',
                        style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showSubmissionReport(
                            context, submissionId, username),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.flag_outlined,
                              color: Colors.white24, size: 14),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _medal(int i) {
    switch (i) {
      case 0: return '🥇';
      case 1: return '🥈';
      case 2: return '🥉';
      default: return '${i + 1}';
    }
  }

  void _showSubmissionReport(
      BuildContext context, String submissionId, String username) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SubmissionReportSheet(
        submissionId: submissionId,
        username: username,
      ),
    );
  }
}

// ── Rules modal shown before camera opens ──────────────────────────────────────

class _CameraRulesSheet extends StatelessWidget {
  final VoidCallback onConfirm;
  const _CameraRulesSheet({required this.onConfirm});

  static const _accent = Color(0xFF7B2CBF);

  static const _rules = [
    (
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF9B4DCA),
      title: 'AuraSense is the judge',
      body: 'Your performance is scored by AI — no human bias.',
    ),
    (
      icon: Icons.content_copy_rounded,
      color: Color(0xFF54A0FF),
      title: 'Copy the challenge closely',
      body: 'Match the timing, movement, and sound as precisely as you can.',
    ),
    (
      icon: Icons.checkroom_outlined,
      color: Color(0xFFFF6B9D),
      title: 'Only performance counts',
      body: 'Clothes, hair, location and appearance do not affect your score.',
    ),
    (
      icon: Icons.shield_outlined,
      color: Color(0xFF22C55E),
      title: 'Play fair',
      body: 'Duplicate uploads and fake submissions will be penalised.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Before you record',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Quick reminder',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Rules list
          ..._rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: r.color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(r.icon, color: r.color, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.body,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          // CTA
          GestureDetector(
            onTap: onConfirm,
            child: Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  "I'm Ready — Open Camera",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Dismiss
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              'Not now',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Report challenge sheet ────────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;
  const _ReportSheet({required this.challengeId, required this.challengeTitle});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _accent = Color(0xFF7B2CBF);

  static const _reasons = [
    'Inappropriate content',
    'Misleading or false challenge',
    'Spam or duplicate',
    'Dangerous or unsafe activity',
    'Other',
  ];

  String? _selected;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('reports').add({
        'challengeId': widget.challengeId,
        'challengeTitle': widget.challengeTitle,
        'reportedBy': uid ?? 'anonymous',
        'reason': _selected,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report submitted. Thank you for your feedback.'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_rounded,
                    color: Colors.redAccent, size: 18),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report challenge',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Select a reason',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Reasons
          ..._reasons.map((reason) {
            final selected = _selected == reason;
            return GestureDetector(
              onTap: () => setState(() => _selected = reason),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? _accent.withValues(alpha: 0.65)
                        : Colors.white.withValues(alpha: 0.10),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white60,
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: _accent, size: 18),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 18),

          // Submit
          GestureDetector(
            onTap: _selected == null || _submitting ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: _selected == null
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)]),
                color: _selected == null
                    ? Colors.white.withValues(alpha: 0.08)
                    : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2),
                      )
                    : Text(
                        'Submit Report',
                        style: TextStyle(
                          color: _selected == null
                              ? Colors.white38
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Submission report sheet ───────────────────────────────────────────────────

class _SubmissionReportSheet extends StatefulWidget {
  final String submissionId;
  final String username;
  const _SubmissionReportSheet(
      {required this.submissionId, required this.username});

  @override
  State<_SubmissionReportSheet> createState() => _SubmissionReportSheetState();
}

class _SubmissionReportSheetState extends State<_SubmissionReportSheet> {
  static const _accent = Color(0xFF7B2CBF);

  static const _reasons = [
    'Inappropriate content',
    'Fake or staged submission',
    'Spam or duplicate',
    'Dangerous or unsafe activity',
    'Other',
  ];

  String? _selected;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('reports').add({
        'submissionId': widget.submissionId,
        'reportedUsername': widget.username,
        'reportedBy': uid ?? 'anonymous',
        'reason': _selected,
        'type': 'submission',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report submitted. Thank you.'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_rounded,
                    color: Colors.redAccent, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Report submission',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text('@${widget.username}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ..._reasons.map((reason) {
            final selected = _selected == reason;
            return GestureDetector(
              onTap: () => setState(() => _selected = reason),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? _accent.withValues(alpha: 0.65)
                        : Colors.white.withValues(alpha: 0.10),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(reason,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white60,
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          )),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: _accent, size: 18),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _selected == null || _submitting ? null : _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: _selected == null
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)]),
                color: _selected == null
                    ? Colors.white.withValues(alpha: 0.08)
                    : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2),
                      )
                    : Text(
                        'Submit Report',
                        style: TextStyle(
                          color: _selected == null
                              ? Colors.white38
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Like button with animated heart + count ───────────────────────────────────

class _LikeButton extends StatefulWidget {
  final bool liked;
  final int count;
  final bool busy;
  final VoidCallback onTap;

  const _LikeButton({
    required this.liked,
    required this.count,
    required this.busy,
    required this.onTap,
  });

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      lowerBound: 0.75,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(_LikeButton old) {
    super.didUpdateWidget(old);
    if (widget.liked != old.liked) {
      _ctrl.reverse().then((_) => _ctrl.forward());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _ctrl,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.liked
                    ? Colors.pinkAccent.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: widget.busy
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.pinkAccent, strokeWidth: 2),
                      ),
                    )
                  : Icon(
                      widget.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_outline_rounded,
                      color: widget.liked ? Colors.pinkAccent : Colors.white,
                      size: 20,
                    ),
            ),
          ),
          if (widget.count > 0) ...[
            const SizedBox(height: 2),
            Text(
              widget.count >= 1000
                  ? '${(widget.count / 1000).toStringAsFixed(1)}k'
                  : '${widget.count}',
              style: TextStyle(
                color: widget.liked ? Colors.pinkAccent : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
