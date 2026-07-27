import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/api_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../widgets/achievement_card.dart' show kChallengeBaseUrl;
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
  bool _isPaused = false;
  String _thumbnailUrl = '';
  // Some entry points (e.g. search results) construct this screen without a
  // videoUrl/instructions — they're filled in from the full challenge fetch
  // below. Seeded from the widget so screens that already have this data
  // (trending, dashboard, etc.) render instantly without waiting on the fetch.
  late String _videoUrl = widget.videoUrl;
  late String _instructions = widget.instructions;

  // Submissions
  List<Map<String, dynamic>> _submissions = [];
  Map<String, dynamic>? _mySubmission;
  bool _submissionsLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChallengeData();
    _fetchSubmissions();
    // Start warming the reference-video cache immediately — by the time the
    // user reads the challenge, opens the rules sheet, and taps Record,
    // CameraScreen's ghost overlay can play from disk instead of streaming.
    if (_videoUrl.isNotEmpty) VideoCacheService.ensureCached(_videoUrl);
  }

  Future<void> _fetchChallengeData() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final data = await ChallengesService().fetchChallenge(widget.challengeId);
      if (data == null || !mounted) return;
      final c = normaliseChallenge(data);
      setState(() {
        _auraPoints = c['starsCount'] as int;
        _isPaused = false;
        _thumbnailUrl = c['thumbnailUrl'] as String? ?? '';
        if (_videoUrl.isEmpty) _videoUrl = c['videoUrl'] as String? ?? '';
        if (_instructions.isEmpty) {
          _instructions = c['instructions'] as String? ?? '';
        }
      });
      if (_videoUrl.isNotEmpty) VideoCacheService.ensureCached(_videoUrl);
    } catch (_) {}
  }

  Future<void> _fetchSubmissions() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final subs = await ChallengesService().fetchSubmissions(widget.challengeId);
      final mine = await ChallengesService().fetchMySubmission(widget.challengeId);
      if (!mounted) return;
      setState(() {
        _submissions = subs;
        _mySubmission = mine;
        _submissionsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _submissionsLoading = false);
    }
  }

  // Bookmark/save removed — no backend endpoint exists to persist it
  // (only GET /profile/saved-challenges exists, no write). The old Firestore
  // write here also had no Firebase Auth session backing it for REST-API
  // authenticated users, so it silently failed with a permission error on
  // every attempt. Re-add once a real POST endpoint exists.

  // Like removed — same issue as bookmark/save: no backend endpoint for a
  // challenge-level like (only POST /videos/{id}/like exists, unrelated),
  // and the old Firestore write had no Firebase Auth session backing it for
  // REST-API authenticated users, so it silently failed every time.

  void _share() {
    final link = '$kChallengeBaseUrl/${widget.challengeId}';
    Share.share(
      'Check out this challenge on Aura: "${widget.title}" 🌟\n\n'
      'Think you can complete it? 💪\n\n'
      '👉 $link',
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

    if (_videoUrl.isEmpty) return;
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(_videoUrl));
    await _videoController!.initialize();
    if (!mounted) return;
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
                referenceVideoUrl: _videoUrl,
              ),
            ),
          );
        },
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
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).padding.bottom + 28),
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
            _sheetOption(
              icon: Icons.videocam_rounded,
              label: 'Record Now',
              subtitle: 'Use your camera to record',
              onTap: () {
                Navigator.pop(context);
                _showCameraRulesModal();
              },
            ),
            const SizedBox(height: 4),
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

                        // Video player
                        _buildVideoSection(),

                        // Details section
                        _buildDetailsSection(),

                        // Rewards section
                        _buildRewardsSection(),

                        // Submissions section
                        _buildSubmissionsSection(),

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
                  children: [Expanded(child: _buildBottomButton())],
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

  // ── Bottom button (paused / already submitted / take) ─────────────────────
  Widget _buildBottomButton() {
    if (_isPaused) {
      return Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.40)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pause_circle_outline_rounded,
                color: Colors.amber.withValues(alpha: 0.80), size: 20),
            const SizedBox(width: 8),
            Text('Submissions Paused',
                style: TextStyle(
                    color: Colors.amber.withValues(alpha: 0.80),
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    if (_mySubmission != null) {
      final score = (_mySubmission!['aiScore'] as num?)?.toInt() ?? 0;
      final approved = submissionStatusFromApi(_mySubmission!) == 'approved';
      return GestureDetector(
        onTap: _showTakeChallengeSheet,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: approved
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: approved
                  ? Colors.green.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                approved ? Icons.check_circle_rounded : Icons.replay_rounded,
                color: approved ? Colors.greenAccent : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                approved
                    ? 'Submitted · $score pts — Try again?'
                    : 'Try again',
                style: TextStyle(
                    color: approved ? Colors.greenAccent : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
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
    );
  }

  // ── Submissions section ────────────────────────────────────────────────────
  Widget _buildSubmissionsSection() {
    if (_submissionsLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: SizedBox(
          height: 60,
          child: Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
        ),
      );
    }
    if (_submissions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Top Submissions',
                style: TextStyle(
                    color: _accent, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_submissions.length}',
                  style: const TextStyle(
                      color: Color(0xFFD4A8FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _submissions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  _buildSubmissionTile(_submissions[i], i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionTile(Map<String, dynamic> sub, int rank) {
    final videoUrl = sub['videoUrl'] as String? ?? '';
    final score = (sub['aiScore'] as num?)?.toInt() ?? 0;
    final approved = submissionStatusFromApi(sub) == 'approved';
    // GET /challenges/{id}/submissions never joins a display name for the
    // submitter — `userId` comes back as either a bare id string or a
    // populated `{_id}` object with no name field, and there's no public
    // endpoint that resolves a player id to a name (creators/brands lookups
    // 404 for regular players; player profiles are otherwise private). Fall
    // back to a rank-based label instead of a fabricated or identical name.
    final username = 'Player ${rank + 1}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 90,
        child: Stack(
          fit: StackFit.expand,
          children: [
            videoUrl.isNotEmpty
                ? VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover)
                : Container(color: const Color(0xFF1A1A2E)),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75)
                  ],
                ),
              ),
            ),
            if (rank < 3)
              Positioned(
                top: 6,
                left: 6,
                child: Text(
                  rank == 0 ? '🥇' : rank == 1 ? '🥈' : '🥉',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            Positioned(
              bottom: 6,
              left: 4,
              right: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                  if (approved && score > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$score pts',
                      style: const TextStyle(
                          color: Color(0xFFD4A8FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
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
                      videoUrl: _videoUrl,
                      thumbnailUrl: _thumbnailUrl,
                      fit: BoxFit.cover)
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
                  // Numbered steps already carry their own "1. "/"2. " marker
                  // — don't also prepend a bullet.
                  if (!_isNumberedInstructions)
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
  static final _numberedLineRegExp = RegExp(r'^\d+\.\s');

  // Challenge-creation screens join steps as "1. ...\n2. ...\n3. ...", so
  // every line is already its own numbered step — not a one-line tagline
  // followed by free-form details. Treating line 1 as a "subtitle" in that
  // case rips the first step out of the list, and prefixing the rest with
  // "• " on top of their own "2. "/"3. " produces "• 2. Execute cleanly.".
  bool get _isNumberedInstructions {
    final lines = _instructions
        .trim()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isNotEmpty && lines.every(_numberedLineRegExp.hasMatch);
  }

  String get _subtitle {
    final text = _instructions.trim();
    if (text.isEmpty || _isNumberedInstructions) return '';
    final firstLine = text.split('\n').first.trim();
    if (firstLine.length <= 80 && _instructions.contains('\n')) {
      return firstLine;
    }
    return '';
  }

  List<String> get _bulletPoints {
    final text = _instructions.trim();
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
      final uid = await ApiClient().userId;
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
      final uid = await ApiClient().userId;
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

