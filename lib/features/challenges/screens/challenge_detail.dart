import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/challenge_analytics_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/brands_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../core/services/video_prewarm_cache.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../core/utils/video_diag.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../leaderboard/screens/challenge_leaderboard_screen.dart';
import '../widgets/achievement_card.dart' show kChallengeBaseUrl;
import 'camera_screen.dart';
import '../../../core/services/safety_service.dart';
import '../../../shared/widgets/safety_sheets.dart';

class ChallengeDetail extends StatefulWidget {
  final String title;
  final String instructions;
  final String videoUrl;
  final String challengeId;

  /// Where the user opened this from (home, search, deep_link, ...), for
  /// analytics only.
  final String source;

  /// Opens the "Take this Challenge" sheet as soon as the challenge is known to be
  /// open (the reels' Aura button). A paused or unreachable challenge just shows the page.
  final bool startTaking;

  const ChallengeDetail({
    super.key,
    required this.title,
    required this.instructions,
    required this.videoUrl,
    required this.challengeId,
    this.source = 'unknown',
    this.startTaking = false,
  });

  @override
  State<ChallengeDetail> createState() => _ChallengeDetailState();
}

class _ChallengeDetailState extends State<ChallengeDetail> {
  static const _bg = Color(0xFF0D0D1A);
  static const _accent = Color(0xFF7B2CBF);

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoStarted = false; // true once user taps play
  bool _isFullscreen = false;
  // Set while _prewarmVideo() is downloading/initializing a controller in
  // the background, ahead of the user ever tapping play. _initAndPlayVideo()
  // awaits this instead of doing its own initialize() — by the time the
  // user actually taps, this has usually already resolved, so play starts
  // with no visible load at all instead of showing the loading spinner.
  Future<void>? _prewarmFuture;

  // Challenge data
  bool _isPaused = false;
  // `_isPaused` only becomes trustworthy once _fetchChallengeData's GET
  // resolves — until then (or if it fails) it's just the `false` default,
  // which used to leave the "Take this Challenge" CTA tappable for however
  // long the request takes, or forever on a swallowed error. Gate the CTA
  // on this instead of on _isPaused alone so a slow/failed status check
  // can't be raced into recording+uploading a take for a closed challenge.
  bool _statusReady = false;
  bool _statusCheckFailed = false;
  String _thumbnailUrl = '';
  // Some entry points (e.g. search results) construct this screen without a
  // videoUrl/instructions — they're filled in from the full challenge fetch
  // below. Seeded from the widget so screens that already have this data
  // (trending, dashboard, etc.) render instantly without waiting on the fetch.
  late String _videoUrl = widget.videoUrl;
  late String _instructions = widget.instructions;
  bool _detailsExpanded = false;

  // Submissions
  Map<String, dynamic>? _mySubmission;

  // Owner info for the challenge_view event, filled by _fetchChallengeData.
  String? _ownerType;
  String? _ownerId;
  // For the report / block menu (ADR 117).
  String _ownerName = '';
  String _videoId = '';
  String? _myId;

  // For the stats strip and owner chip under the video (client, 26 Nov 2026:
  // the "immersive" redesign, option A).
  String _ownerAvatar = '';
  int _takenCount = 0;
  DateTime? _endDate;

  bool get _isOwnChallenge => (_ownerId ?? '').isNotEmpty && _ownerId == _myId;

  // Anchors the iOS/iPadOS share-sheet popover to the actual button instead
  // of an unset origin — see _share().
  final _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Opening the detail page shows the challenge and plays its video.
    ChallengeAnalyticsService().recordImpression(widget.challengeId);
    ChallengeAnalyticsService().recordVideoView(widget.challengeId);
    // Logged once the challenge fetch settles (success or failure) so the
    // event can carry owner_type / owner_id; deliberately not gated on
    // `mounted` — the view happened even if the user already backed out.
    _fetchChallengeData().whenComplete(() {
      AnalyticsService().logChallengeView(
        widget.challengeId,
        source: widget.source,
        ownerType: _ownerType,
        ownerId: _ownerId,
      );
      // Same gate as the Take this Challenge button: only once the status is known and open.
      if (widget.startTaking &&
          mounted &&
          _statusReady &&
          !_statusCheckFailed &&
          !_isPaused) {
        _showCameraRulesModal();
      }
    });
    _fetchSubmissions();
    // Start warming the reference-video cache immediately — by the time the
    // user reads the challenge, opens the rules sheet, and taps Record,
    // CameraScreen's ghost overlay can play from disk instead of streaming.
    if (_videoUrl.isNotEmpty) VideoCacheService.ensureCached(_videoUrl);
    // Also pre-initialize the on-screen player itself (not just the disk
    // cache, which is skipped entirely for HLS — see _doPrewarm) so tapping
    // play has nothing left to wait on.
    _prewarmVideo();
  }

  Future<void> _fetchChallengeData() async {
    if (widget.challengeId.isEmpty) {
      // Nothing to check the status of — don't leave the CTA stuck loading.
      if (mounted) setState(() => _statusReady = true);
      return;
    }
    try {
      final data = await ChallengesService().fetchChallenge(widget.challengeId);
      if (!mounted) return;
      if (data == null) {
        // fetchChallenge() already swallows the real error — we only know
        // the status couldn't be confirmed. Fail closed instead of leaving
        // _isPaused at its `false` default, which would let the user record
        // and upload a take before finding out server-side.
        setState(() {
          _statusReady = true;
          _statusCheckFailed = true;
        });
        return;
      }
      final c = normaliseChallenge(data);
      _ownerType = c['sourceType'] as String?;
      _ownerId = c['creatorId'] as String?;
      _ownerName = c['creatorName'] as String? ?? '';
      _videoId = c['videoId'] as String? ?? '';
      _ownerAvatar = c['creatorAvatar'] as String? ?? '';
      _takenCount = c['participants'] as int? ?? c['submissionsCount'] as int? ?? 0;
      _endDate = DateTime.tryParse('${c['endDate'] ?? ''}')?.toLocal();
      // The challenge carries only the brand's id: look up its name and logo
      // for the owner chip (best effort; the chip says "Brand" until then).
      if (_ownerType == 'Brand' &&
          _ownerName.isEmpty &&
          (_ownerId ?? '').isNotEmpty) {
        _loadBrand(_ownerId!);
      }
      _myId = await ApiClient().userId;
      if (!mounted) return;
      setState(() {
        // POST /challenges/{id}/submissions requires `status: approved`
        // (openapi.yaml) — anything else (pending/rejected/flagged) fails
        // server-side with "not accepting submissions" only after the user
        // has already recorded and uploaded a take. Surface that up front
        // instead of hardcoding this to false.
        _isPaused = c['status'] != 'approved';
        _statusReady = true;
        _thumbnailUrl = c['thumbnailUrl'] as String? ?? '';
        // Per openapi.yaml, Challenge.videoUrl is resolved fresh on every
        // read — a presigned (expiring) RAW URL while the reference video
        // is still processing, a stable public HLS URL once done. Callers
        // that already had a videoUrl (nearly every list screen) pass in
        // whatever they fetched whenever *their* list loaded, which can be a
        // since-expired presigned URL by the time the user gets here. Always
        // prefer this fetch's fresh value over that stale one — the old
        // `if (_videoUrl.isEmpty)` guard only existed for entry points like
        // search results that pass '', but it also meant a stale presigned
        // URL from anywhere else was kept forever, silently breaking
        // CameraScreen's ghost overlay for any challenge still processing.
        final freshVideoUrl = c['videoUrl'] as String? ?? '';
        final urlChanged =
            freshVideoUrl.isNotEmpty && freshVideoUrl != _videoUrl;
        if (freshVideoUrl.isNotEmpty) _videoUrl = freshVideoUrl;
        if (_instructions.isEmpty) {
          _instructions = c['instructions'] as String? ?? '';
        }
        // The widget-seeded URL a caller passed in may have been a stale/
        // expired presigned one (see comment above) — if this fetch just
        // replaced it and the user hasn't already committed to playing the
        // old one, restart prewarming against the real URL instead of
        // leaving a dead controller sitting there.
        if (urlChanged && !_videoStarted) {
          _videoController?.dispose();
          _videoController = null;
          _videoInitialized = false;
          _prewarmFuture = null;
        }
      });
      if (_videoUrl.isNotEmpty) {
        VideoCacheService.ensureCached(_videoUrl);
        if (!_videoStarted) _prewarmVideo();
      }
    } catch (_) {
      // Same fail-closed reasoning as the data == null branch above.
      if (mounted) {
        setState(() {
          _statusReady = true;
          _statusCheckFailed = true;
        });
      }
    }
  }

  Future<void> _loadBrand(String id) async {
    final raw = await BrandsService().fetchBrand(id);
    if (raw == null || !mounted) return;
    final b = normaliseBrand(raw);
    setState(() {
      _ownerName = b['displayName'] as String? ?? '';
      _ownerAvatar = b['avatar'] as String? ?? '';
    });
  }

  Future<void> _fetchSubmissions() async {
    if (widget.challengeId.isEmpty) return;
    try {
      final mine = await ChallengesService().fetchMySubmission(
        widget.challengeId,
      );
      if (!mounted) return;
      setState(() => _mySubmission = mine);
    } catch (_) {}
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

  Future<void> _share() async {
    ChallengeAnalyticsService().recordShare(widget.challengeId);
    AnalyticsService().logShare(
      contentType: 'challenge',
      itemId: widget.challengeId,
    );
    final link = '$kChallengeBaseUrl/${widget.challengeId}';
    try {
      // sharePositionOrigin anchors the share-sheet popover on iPad/Mac and
      // has no documented effect on iPhone, but omitting it is also the one
      // change several reported "share sheet silently does nothing on iOS"
      // issues against this plugin were traced to — cheap and harmless to
      // always supply. Previously this call was unguarded fire-and-forget,
      // so any PlatformException from it (this is the only Share.share call
      // in the app not already wrapped) had nowhere to surface at all.
      final box =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await Share.share(
        'Check out this challenge on Aura: "${widget.title}" 🌟\n\n'
        'Think you can complete it? 💪\n\n'
        '👉 $link',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the share sheet: $e')),
      );
    }
  }

  /// Report the challenge, report its video, or block whoever posted it (ADR 117).
  /// Platform challenges have no blockable owner; your own challenge has nothing to block.
  void _showSafetyMenu() {
    final owner = _ownerId ?? '';
    final canBlock =
        owner.isNotEmpty &&
        owner != _myId &&
        (_ownerType == 'Creator' || _ownerType == 'Brand');
    final name =
        _ownerName.isNotEmpty
            ? _ownerName
            : (_ownerType == 'Brand' ? 'this brand' : 'this creator');
    showSafetyMenu(context, [
      SafetyMenuItem(
        key: const Key('safety-report-challenge'),
        icon: Icons.flag_outlined,
        label: 'Report challenge',
        onTap: _showReportSheet,
      ),
      if (_videoId.isNotEmpty && owner != _myId)
        SafetyMenuItem(
          key: const Key('safety-report-video'),
          icon: Icons.videocam_off_outlined,
          label: 'Report video',
          onTap:
              () => showReportSheet(
                context,
                title: 'Report this video',
                submit:
                    (reason, details) => SafetyService().reportVideo(
                      _videoId,
                      reason,
                      details: details,
                    ),
              ),
        ),
      if (canBlock)
        SafetyMenuItem(
          key: const Key('safety-block-owner'),
          icon: Icons.block_rounded,
          label: 'Block $name',
          danger: true,
          onTap:
              () => blockWithConfirm(
                context,
                userId: owner,
                name: name,
                isBrand: _ownerType == 'Brand',
                onBlocked: () {
                  if (mounted) Navigator.pop(context);
                },
              ),
        ),
    ]);
  }

  void _showReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (ctx) => _ReportSheet(
            challengeId: widget.challengeId,
            challengeTitle: widget.title,
          ),
    );
  }

  // Builds and fully initializes a controller for [url] (throws if
  // initialize() fails — callers decide how to handle that). Prefers, in
  // order: an already-initialized controller a *list* screen prewarmed
  // ahead of navigation (VideoPrewarmCache — e.g. the home feed warming a
  // card before the user even taps it), then a fully-downloaded local file
  // if VideoCacheService managed to cache one (it can't for HLS — see that
  // service's doc comment), then a plain network stream.
  Future<VideoPlayerController> _buildController(String url) async {
    final prewarmed = VideoPrewarmCache.take(url);
    if (prewarmed != null) return prewarmed;

    final cachedPath = await VideoCacheService.ensureCached(url);
    // Without mixWithOthers, ExoPlayer/AVAudioSession request *exclusive*
    // audio focus and their default focus-loss handling auto-pauses
    // playback for any transient system sound (a notification tone, a
    // keyboard click, an incoming-call banner, a Bluetooth chime,
    // Assistant's hotword, ...) — with no plugin-level signal to auto-resume
    // afterward, so it looks like the video "randomly pauses itself." This
    // is a short instructional demo clip, not long-form content competing
    // for the user's attention, so letting it mix with (rather than duck/
    // interrupt) other audio is the right trade-off here.
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller =
        cachedPath != null
            ? VideoPlayerController.file(
              File(cachedPath),
              videoPlayerOptions: options,
            )
            : VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: options,
            );
    try {
      await controller.initialize();
    } catch (e) {
      // Logged (not shown to the user) via debugPrint inside
      // describeVideoFailure — grep device logs for `[videodiag]`.
      describeVideoFailure(
        e,
        where: 'ChallengeDetail preview',
        url: url,
        fromCache: cachedPath != null,
        playerError: controller.value.errorDescription,
      );
      controller.dispose();
      rethrow;
    }
    return controller;
  }

  // Fire-and-forget: builds and initializes a controller for the current
  // _videoUrl in the background, well before the user taps play. No-op if
  // one's already in flight or done, or the URL isn't known yet.
  void _prewarmVideo() {
    if (_videoUrl.isEmpty || _prewarmFuture != null) return;
    _prewarmFuture = _doPrewarm(_videoUrl);
  }

  Future<void> _doPrewarm(String url) async {
    VideoPlayerController controller;
    try {
      controller = await _buildController(url);
    } catch (_) {
      return; // leave _videoController null — _initAndPlayVideo falls back
    }
    // The URL can change mid-flight (a fresher one lands from
    // _fetchChallengeData) or the screen can be popped before this
    // resolves — either way this controller is stale/unwanted, so just
    // release it rather than assigning it anywhere.
    if (!mounted || url != _videoUrl) {
      controller.dispose();
      return;
    }
    _videoController = controller;
    if (mounted) setState(() => _videoInitialized = true);
  }

  Future<void> _initAndPlayVideo() async {
    if (_videoStarted) {
      // Already loaded from a previous play — reopen fullscreen instead of
      // playing inline (the inline card has no aspect-correct player).
      if (_videoInitialized) _enterFullscreen();
      return;
    }

    setState(() => _videoStarted = true);

    if (_videoUrl.isEmpty) return;

    // The common case: prewarming already finished (or is far enough along)
    // that this resolves with no visible wait at all.
    _prewarmVideo();
    await _prewarmFuture;
    if (!mounted) return;

    if (_videoController == null) {
      // Prewarm never landed (failed, or raced a mid-flight URL change) —
      // fall back to loading it fresh right now, same as before prewarming
      // existed.
      try {
        _videoController = await _buildController(_videoUrl);
      } catch (_) {
        // Previously left _videoStarted true / _videoInitialized false, i.e.
        // an endless spinner with no way out. Reset so the play button comes
        // back, and show a friendly message instead of the raw diagnostic
        // dump (still logged via debugPrint inside describeVideoFailure —
        // grep device logs for `[videodiag]`).
        if (!mounted) return;
        setState(() => _videoStarted = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This video couldn't be played on your device. Please try again.",
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _videoInitialized = true);
    }

    _videoController!.addListener(_reportWatchProgress);
    _enterFullscreen();
    _videoController!.play();
  }

  // Throttled inside the service; safe to fire on every controller tick.
  void _reportWatchProgress() {
    final v = _videoController?.value;
    if (v == null || !v.isInitialized || !v.isPlaying) return;
    ChallengeAnalyticsService().recordWatchProgress(
      widget.challengeId,
      watched: v.position,
      total: v.duration > Duration.zero ? v.duration : null,
    );
  }

  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Videos are recorded vertically — lock portrait rather than landscape.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _exitFullscreen() {
    _videoController?.pause();
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildVideoControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      child: AnimatedBuilder(
        animation: _videoController!,
        builder: (context, _) {
          final value = _videoController!.value;
          return Row(
            children: [
              IconButton(
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () {
                  if (value.isPlaying) {
                    _videoController!.pause();
                  } else {
                    _videoController!.play();
                  }
                },
              ),
              Text(
                _formatDuration(value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: VideoProgressIndicator(
                  _videoController!,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  colors: VideoProgressColors(
                    playedColor: _accent,
                    bufferedColor: Colors.white.withValues(alpha: 0.3),
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCameraRulesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _CameraRulesSheet(
            onConfirm: () {
              Navigator.of(ctx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CameraScreen(
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

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final v = _videoController?.value;
    if (v != null && v.isInitialized && v.position > Duration.zero) {
      ChallengeAnalyticsService().recordWatchProgress(
        widget.challengeId,
        watched: v.position,
        total: v.duration > Duration.zero ? v.duration : null,
        flush: true,
      );
    }
    ChallengeAnalyticsService().endWatchSession(widget.challengeId);
    _videoController?.removeListener(_reportWatchProgress);
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
            // Client, 26 Nov 2026 (option A, "immersive"): the video runs edge
            // to edge under the status bar and fades into the page, with the
            // title on it; a stats strip and the instructions follow.
            // Client, 26 Nov 2026: with short instructions the page left a big
            // empty gap above the bottom bar. The video now grows into any
            // spare height, so the stats and text sit just above the bar; long
            // text still scrolls (the video then keeps its normal height).
            Positioned.fill(
              child: LayoutBuilder(
                builder:
                    (context, viewport) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: viewport.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildVideoSection()),
                              _buildStatsStrip(),
                              _buildDetailsSection(),
                              // Space for the sticky bar
                              SizedBox(
                                height:
                                    MediaQuery.of(context).padding.bottom + 104,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ),
            ),

            // ── Back / share / report over the video ─────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _glassIconButton(
                    onTap: () => Navigator.pop(context),
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    tooltip: 'Back',
                  ),
                  const Spacer(),
                  _glassIconButton(
                    key: _shareButtonKey,
                    onTap: _share,
                    icon: Icons.share_rounded,
                    tooltip: 'Share',
                  ),
                  // Report / block make no sense on your own challenge — the
                  // menu would only offer "report yourself".
                  if (!_isOwnChallenge) ...[
                    const SizedBox(width: 10),
                    _glassIconButton(
                      key: const Key('challenge-safety-menu'),
                      onTap: _showSafetyMenu,
                      icon: Icons.flag_outlined,
                      tooltip: 'Report',
                    ),
                  ],
                ],
              ),
            ),

            // ── Sticky bottom bar: leaderboard + take the challenge ──────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  MediaQuery.of(context).padding.bottom + 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _bg.withValues(alpha: 0),
                      _bg.withValues(alpha: 0.96),
                      _bg,
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
                child: Row(
                  children: [
                    _buildLeaderboardButton(),
                    const SizedBox(width: 10),
                    Expanded(child: _buildBottomButton()),
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
                        },
                        child: Center(
                          child:
                              _videoInitialized
                                  ? AspectRatio(
                                    aspectRatio: correctedVideoAspectRatio(
                                      _videoController!.value,
                                    ),
                                    child: VideoPlayer(_videoController!),
                                  )
                                  : const CircularProgressIndicator(
                                    color: _accent,
                                  ),
                        ),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: _exitFullscreen,
                          ),
                        ),
                      ),
                      if (_videoInitialized)
                        AnimatedBuilder(
                          animation: _videoController!,
                          builder: (context, _) {
                            final value = _videoController!.value;
                            // The reference clip streams over the network, so
                            // a slow connection can stall mid-playback. Left
                            // unhandled, VideoPlayer just silently holds the
                            // last decoded frame — indistinguishable from a
                            // genuine freeze — instead of showing anything
                            // that tells the user it's still alive and will
                            // resume once more data arrives.
                            if (value.isBuffering) {
                              return const Center(
                                child: IgnorePointer(
                                  child: CircularProgressIndicator(
                                    color: _accent,
                                  ),
                                ),
                              );
                            }
                            if (value.isPlaying) {
                              return const SizedBox.shrink();
                            }
                            return Center(
                              child: IgnorePointer(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.85),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (_videoInitialized)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SafeArea(
                            top: false,
                            child: _buildVideoControls(),
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
    if (!_statusReady) {
      return Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_statusCheckFailed) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _statusReady = false;
            _statusCheckFailed = false;
          });
          _fetchChallengeData();
        },
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: const Center(
            child: Text(
              "Couldn't check availability — Tap to retry",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    // A creator / brand can't take part in their own challenge (the backend
    // 403s the submission), so the owner gets a label instead of the CTA.
    if (_isOwnChallenge) {
      return Container(
        key: const Key('own-challenge-cta'),
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_rounded, color: Colors.white70, size: 20),
            SizedBox(width: 8),
            Text(
              'Your challenge — you can\'t take part in it',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

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
            Icon(
              Icons.pause_circle_outline_rounded,
              color: Colors.amber.withValues(alpha: 0.80),
              size: 20,
            ),
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
      );
    }

    // Deliberately no special-case here for _mySubmission != null — the CTA
    // stays "Take this Challenge" even after a submission exists, so users
    // can keep retaking the challenge without the button changing style.
    // Client, 26 Nov 2026: straight to the rules, no "Record Now" sheet first
    // (recording was its only option).
    return GestureDetector(
      onTap: _showCameraRulesModal,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29),
          gradient: const LinearGradient(
            colors: [Color(0xFF9A45EA), Color(0xFF6A1FB4)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.50),
              blurRadius: 28,
              offset: const Offset(0, 10),
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
              wordSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  // ── Leaderboard button ─────────────────────────────────────────────────────
  // Always visible on every challenge detail page. _mySubmission only becomes
  // non-null after a real GET /challenges/{id}/submissions/me hit in
  // _fetchSubmissions() — used here to gate the *tap*, not the button's
  // visibility: a viewer who hasn't taken this specific challenge yet gets a
  // locked notice instead of opening an empty/meaningless board for a
  // challenge they haven't scored on.
  Widget _buildLeaderboardButton() {
    final participated = _mySubmission != null;
    return Tooltip(
      message: 'See Aura Farmers',
      child: GestureDetector(
        key: const Key('challenge-leaderboard'),
        onTap:
            participated
                ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ChallengeLeaderboardScreen(
                          challengeId: widget.challengeId,
                          challengeTitle: widget.title,
                        ),
                  ),
                )
                : _showLeaderboardLockedNotice,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        participated
                            ? _accent.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          participated
                              ? _accent.withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Icon(
                    Icons.leaderboard_rounded,
                    color: participated ? Colors.white : Colors.white60,
                    size: 22,
                  ),
                ),
              ),
              // Locked until you've taken it (see the notice).
              if (!participated)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1A33),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white70,
                      size: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassIconButton({
    Key? key,
    required VoidCallback onTap,
    required IconData icon,
    required String tooltip,
    double size = 19,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.30),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Icon(icon, color: Colors.white, size: size),
            ),
          ),
        ),
      ),
    );
  }

  void _showLeaderboardLockedNotice() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Take this challenge once to unlock its Aura Farmers 🔓',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E1E2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Video section ──────────────────────────────────────────────────────────
  Widget _buildVideoSection() {
    final size = MediaQuery.of(context).size;
    final height =
        (size.width * 1.22).clamp(320.0, size.height * 0.62).roundToDouble();
    // At least this tall; taller when the page has spare height (see build).
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: GestureDetector(
        onTap: _initAndPlayVideo,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Actual playback always happens in the fullscreen overlay, so
            // this only ever shows the thumbnail (never the raw VideoPlayer,
            // which would stretch to fill the box).
            // Stops 2px short of the bottom: the thumbnail's last pixel row
            // otherwise peeks out under the fade as a thin line (phone).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 2,
              child: VideoThumbnailWidget(
                videoUrl: _videoUrl,
                thumbnailUrl: _thumbnailUrl,
                fit: BoxFit.cover,
              ),
            ),

            // Dark at the top (for the buttons), clear in the middle, fading
            // into the page at the bottom (for the title).
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Solid page colour for the last few pixels, so no seam
                    // shows where the video ends.
                    stops: [0, 0.2, 0.48, 0.8, 0.97, 1],
                    colors: [
                      Color(0x99000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xD90D0D1A),
                      _bg,
                      _bg,
                    ],
                  ),
                ),
              ),
            ),

            // Dim overlay while loading
            if (_videoStarted && !_videoInitialized)
              Container(color: Colors.black54),

            // Loading spinner (while the tapped video initializes) or play
            // button (idle), never both.
            Align(
              alignment: const Alignment(0, -0.12),
              child:
                  (_videoStarted && !_videoInitialized)
                      ? const CircularProgressIndicator(color: _accent)
                      : ClipOval(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.38),
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
            ),

            // Owner chip and the title, on the fade.
            Positioned(
              left: 20,
              right: 20,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Client, 26 Nov 2026: no difficulty chip, just who posted it.
                  _ownerChip(),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heroTitle.copyWith(
                      fontSize: 30,
                      height: 1.08,
                      shadows: const [
                        Shadow(blurRadius: 18, color: Colors.black54),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({Key? key, required Widget child, Widget? leading}) {
    return Container(
      key: key,
      padding: EdgeInsets.fromLTRB(leading == null ? 11 : 5, 5, 11, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 6)],
            child,
          ],
        ),
      ),
    );
  }

  // Who posted it: the brand or creator with their picture, else an Aura
  // Original with the Aura star.
  Widget _ownerChip() {
    final isBrand = _ownerType == 'Brand';
    final isCreator = _ownerType == 'Creator';
    final String label;
    if ((isBrand || isCreator) && _ownerName.isNotEmpty) {
      label = isBrand ? '$_ownerName · Brand' : _ownerName;
    } else if (isBrand) {
      label = 'Brand';
    } else if (isCreator) {
      label = 'Creator';
    } else {
      label = 'Aura Original';
    }
    final Widget avatar =
        _ownerAvatar.isNotEmpty && (isBrand || isCreator)
            ? CircleAvatar(
              radius: 9,
              backgroundColor: Colors.white12,
              backgroundImage: NetworkImage(_ownerAvatar),
            )
            : Container(
              width: 18,
              height: 18,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1E1A33),
              ),
              child: Image.asset('assets/images/Aura Arena Mono.png'),
            );
    return _chip(
      key: const Key('challenge-owner-chip'),
      leading: avatar,
      child: Text(label),
    );
  }

  // ── Stats strip: reward, how many took it, time left ──────────────────────
  Widget _buildStatsStrip() {
    Widget cell(Widget value, String label) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'ClashDisplay',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                wordSpacing: 4,
                color: Colors.white,
              ),
              child: value,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 32,
      color: Colors.white.withValues(alpha: 0.08),
    );

    final (deadlineValue, deadlineLabel) = _deadline;
    return Container(
      key: const Key('challenge-stats'),
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // A take scores 0-100 and its Aura = its score (functions/index.js).
          cell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/homescreen/separate elements/coin icon.png',
                  height: 15,
                ),
                const SizedBox(width: 5),
                const Text('100'),
              ],
            ),
            'Aura to win',
          ),
          divider(),
          cell(
            Text(_statusReady ? _compactCount(_takenCount) : '–'),
            'Participants',
          ),
          divider(),
          cell(Text(deadlineValue), deadlineLabel),
        ],
      ),
    );
  }

  (String, String) get _deadline {
    if (!_statusReady) return ('–', 'Left');
    final end = _endDate;
    if (end == null) return ('Open', 'No deadline');
    final left = end.difference(DateTime.now());
    if (left.isNegative) return ('Ended', 'Deadline');
    if (left.inDays >= 1) return ('${left.inDays}d', 'Left');
    if (left.inHours >= 1) return ('${left.inHours}h', 'Left');
    return ('${left.inMinutes < 1 ? 1 : left.inMinutes}m', 'Left');
  }

  static String _compactCount(int n) {
    String one(double v) =>
        v >= 10
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(1).replaceAll('.0', '');
    if (n >= 1000000) return '${one(n / 1000000)}M';
    if (n >= 1000) return '${one(n / 1000)}K';
    return '$n';
  }

  // ── Details section ────────────────────────────────────────────────────────
  Widget _buildDetailsSection() {
    final bullets = _bulletPoints;
    if (bullets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_detailsExpanded)
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numbered steps already carry their own "1. "/"2. "
                    // marker — don't also prepend a bullet.
                    if (!_isNumberedInstructions)
                      const Text(
                        '• ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              _instructions.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD6D0EA),
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
            child: Text(
              _detailsExpanded ? 'Read less' : 'Read more',
              style: const TextStyle(
                color: AppColors.accentLight,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
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
    final lines =
        _instructions
            .trim()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
    return lines.isNotEmpty && lines.every(_numberedLineRegExp.hasMatch);
  }

  List<String> get _bulletPoints {
    final text = _instructions.trim();
    if (text.isEmpty) return [];

    // If multi-line, split by newlines
    if (text.contains('\n')) {
      return text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // Single paragraph — split into sentences
    final sentences =
        text
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
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
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
                child: const Icon(
                  Icons.videocam_rounded,
                  color: _accent,
                  size: 20,
                ),
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
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
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
                            color: AppColors.textMuted,
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
              style: TextStyle(color: AppColors.textFaint, fontSize: 14),
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
      await ChallengesService().reportChallenge(
        widget.challengeId,
        challengeReportReasonCode(_selected!),
        remarks: _selected,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Report submitted. Thank you for your feedback.'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
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
                borderRadius: BorderRadius.circular(2),
              ),
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
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Select a reason',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
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
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? _accent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        selected
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
                          color: selected ? Colors.white : AppColors.textMuted,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _accent,
                        size: 18,
                      ),
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
                gradient:
                    _selected == null
                        ? null
                        : const LinearGradient(
                          colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                        ),
                color:
                    _selected == null
                        ? Colors.white.withValues(alpha: 0.08)
                        : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child:
                    _submitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                        : Text(
                          'Submit Report',
                          style: TextStyle(
                            color:
                                _selected == null
                                    ? AppColors.textFaint
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
