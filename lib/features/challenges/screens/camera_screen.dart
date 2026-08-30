import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../../core/globals.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../video/screens/preview_screen.dart';

class CameraScreen extends StatefulWidget {
  final String challengeTitle;
  final String challengeId;
  final String referenceVideoUrl;

  const CameraScreen({
    super.key,
    required this.challengeTitle,
    required this.challengeId,
    this.referenceVideoUrl = '',
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _purple = Color(0xFF7B2CBF);

  CameraController? _cam;
  int _camIndex = 0;
  bool _cameraError = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  // Bumped on every _initCamera call so a stale (superseded) call can tell
  // it's no longer current and avoid clobbering _cam / calling setState with
  // outdated results. Needed because the OS permission dialog pauses/resumes
  // the app lifecycle while a camera init can still be in flight.
  int _initGen = 0;

  // Ghost overlay
  VideoPlayerController? _ghostCtrl;
  bool _ghostOn = true;
  bool _ghostReady = false;
  bool _ghostFailed = false;

  // Recording
  bool _recording = false;
  XFile? _videoFile;
  int _elapsed = 0; // seconds elapsed while recording
  Timer? _timer;

  // Post-ghost auto-stop: once the ghost (reference) clip has played through
  // once, the take is allowed to run at most this many more seconds before
  // it stops itself. A submission much longer than the reference is just
  // dead footage the scorer has to sit through.
  static const _postGhostGraceSeconds = 10;
  // Ghost clip length in whole seconds, captured when recording starts — and
  // only when a ghost is actually playing this take. null ⇒ no ghost, so no
  // auto-stop (the user stops manually, as before).
  int? _ghostLengthSec;
  // Non-null once the ghost has ended and the grace window is counting down;
  // drives the "Auto-stop in Ns" hint on the recording pill.
  int? _graceRemaining;

  // Self-timer: 0 = off, else the chosen delay in seconds before recording
  // actually starts.
  static const _timerOptions = [0, 5, 10, 15];
  int _timerSeconds = 0;
  int? _countdown; // non-null while a countdown is in progress
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera(_camIndex);
    if (widget.referenceVideoUrl.isNotEmpty) _initGhost();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
      _ghostLengthSec = null;
      _graceRemaining = null;
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _countdown = null;
      _ghostCtrl?.pause();
      // Invalidate any in-flight _initCamera call (e.g. one currently
      // awaiting the OS permission dialog, which is itself what triggers
      // this pause) so it won't touch _cam once it eventually settles.
      _initGen++;
      final cam = _cam;
      _cam = null;
      if (mounted) setState(() => _recording = false);
      cam?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      _cameraError = false;
      _initCamera(_camIndex);
      _ghostCtrl?.seekTo(Duration.zero);
    }
  }

  Future<void> _initCamera(int index) async {
    if (cameras.isEmpty) return;
    final gen = ++_initGen;

    // Resolve camera/mic permission ourselves *before* constructing a
    // CameraController. Letting CameraController.initialize() trigger the
    // native prompt itself is what used to race with the app-lifecycle
    // pause/resume that same prompt causes (especially on Android), leading
    // to a live controller being disposed mid-initialize and a stale
    // callback stomping state afterwards → crash. Resolving permission first
    // keeps controller construction and the OS dialog from overlapping.
    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (gen != _initGen) return; // superseded by a newer call meanwhile

    if (!camStatus.isGranted || !micStatus.isGranted) {
      await _cam?.dispose();
      if (gen != _initGen) return; // superseded while disposing
      _cam = null;
      if (mounted) {
        setState(() {
          _cameraError = true;
          _permissionDenied = true;
          _permissionPermanentlyDenied =
              camStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied;
        });
      }
      return;
    }

    // Fully release the previous camera session before opening the new one.
    // dispose() is an async native call that frees the hardware handle —
    // firing it without awaiting let the old session's teardown overlap
    // with the new controller's initialize() acquiring the other lens.
    // Most camera HALs (Android's camera2 in particular) only allow one
    // open session at a time, so that race either threw or, worse, just
    // hung forever: this is what made flipping the camera get stuck on
    // the loading spinner.
    await _cam?.dispose();
    if (gen != _initGen) return; // superseded while disposing
    _cam = null;
    if (mounted) setState(() {}); // show the loading spinner during the swap

    final controller = CameraController(cameras[index], ResolutionPreset.high,
        enableAudio: true);
    _cam = controller;
    try {
      await controller.initialize();
    } catch (_) {
      if (gen != _initGen) return; // stale — a newer call already took over
      if (mounted) {
        setState(() {
          _cam = null;
          _cameraError = true;
          _permissionDenied = false;
        });
      }
      return;
    }
    // Neither this screen nor the app manifest restricts device rotation,
    // so without this, recording while (even briefly) rotated captures the
    // video tagged/encoded in that orientation — the sensor and encoder
    // don't know this UI is portrait-only. That produced submissions that
    // play back sideways everywhere, including in the AI scoring pipeline,
    // which then dinged the user for "recording in the wrong orientation"
    // on a video they held upright for. Best-effort: a lock failure here
    // shouldn't take down an otherwise-working camera.
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    if (gen != _initGen) {
      controller.dispose(); // superseded — don't leak it
      return;
    }
    if (!mounted) return;
    setState(() {
      _camIndex = index;
      _cameraError = false;
      _permissionDenied = false;
    });
  }

  Future<void> _initGhost() async {
    // Prefer a locally cached copy (usually already warmed by
    // ChallengeDetail while the user was still reading the challenge) so
    // playback starts instantly instead of waiting on a network stream.
    final cachedPath = await VideoCacheService.ensureCached(widget.referenceVideoUrl);
    if (!mounted) return;
    _ghostCtrl = cachedPath != null
        ? VideoPlayerController.file(File(cachedPath))
        : VideoPlayerController.networkUrl(Uri.parse(widget.referenceVideoUrl));
    try {
      await _ghostCtrl!.initialize();
    } catch (e) {
      debugPrint('CameraScreen: ghost reference video failed to load: $e');
      if (mounted) setState(() => _ghostFailed = true);
      return;
    }
    if (!mounted) return;
    // Play once, not on a loop: the ghost visibly ending (frozen on its last
    // frame) is the cue that the post-ghost grace window has started, and
    // the auto-stop clock is measured from that single playthrough's length.
    _ghostCtrl!.setLooping(false);
    // Muted: this is a visual overlay guide only — its audio must not bleed
    // into the mic recording of the user's own take.
    await _ghostCtrl!.setVolume(0.0);
    setState(() => _ghostReady = true);
  }

  Future<void> _toggleRecord() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_recording) {
      await _stopRecording();
    } else if (_countdown != null) {
      // Tapping again while the countdown is running cancels it — the
      // record button doubles as the cancel affordance instead of adding a
      // separate control.
      _cancelCountdown();
    } else if (_timerSeconds > 0) {
      _startCountdown();
    } else {
      await _startRecording();
    }
  }

  void _cycleTimer() {
    if (_recording || _countdown != null) return;
    setState(() {
      final i = _timerOptions.indexOf(_timerSeconds);
      _timerSeconds = _timerOptions[(i + 1) % _timerOptions.length];
    });
  }

  void _startCountdown() {
    setState(() => _countdown = _timerSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_countdown ?? 1) - 1;
      if (next <= 0) {
        t.cancel();
        _countdownTimer = null;
        setState(() => _countdown = null);
        // The countdown can run for several seconds — re-check the camera
        // is still around in case the app was backgrounded (which tears
        // _cam down) or the screen popped mid-countdown.
        if (mounted && _cam != null && _cam!.value.isInitialized) {
          _startRecording();
        }
      } else {
        setState(() => _countdown = next);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() => _countdown = null);
  }

  Future<void> _startRecording() async {
    await _cam!.startVideoRecording();
    // Re-assert mute right before playback starts: startVideoRecording()
    // just activated the device's audio-recording session (enableAudio:
    // true), which is a system-level audio route change. On both ExoPlayer
    // and AVPlayer that kind of route change can silently reset a player's
    // volume, so the mute applied once back in _initGhost isn't guaranteed
    // to still hold by the time play() actually runs.
    if (_ghostReady) {
      await _ghostCtrl?.setVolume(0.0);
      _ghostCtrl?.play();
    }
    _elapsed = 0;
    _graceRemaining = null;
    // Arm the auto-stop only when a ghost is actually playing this take; its
    // length is the clock the grace window is measured from. play() above
    // rewinds a completed controller to the start, so a re-take gets the
    // full window again.
    final ghostLen = _ghostReady ? _ghostCtrl?.value.duration : null;
    _ghostLengthSec = (ghostLen != null && ghostLen > Duration.zero)
        ? (ghostLen.inMilliseconds / 1000).ceil()
        : null;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _elapsed++;
      _tickAutoStop();
      setState(() {});
    });
    setState(() {
      _recording = true;
      _videoFile = null;
    });
  }

  // Runs once per second while recording. Before the ghost's length is up
  // nothing happens; after it, we're inside the grace window and count it
  // down; when it's exhausted the recording stops itself.
  void _tickAutoStop() {
    final len = _ghostLengthSec;
    if (len == null) return;
    final graceLeft = len + _postGhostGraceSeconds - _elapsed;
    if (graceLeft <= 0) {
      _graceRemaining = null;
      _stopRecording();
      return;
    }
    _graceRemaining =
        _elapsed >= len ? graceLeft.clamp(1, _postGhostGraceSeconds) : null;
  }

  Future<void> _stopRecording() async {
    if (!_recording) return; // guard re-entry: auto-stop + a manual tap racing
    _timer?.cancel();
    _ghostLengthSec = null;
    _graceRemaining = null;
    _ghostCtrl?.pause();
    _ghostCtrl?.seekTo(Duration.zero);
    final file = await _cam!.stopVideoRecording();
    if (mounted) {
      setState(() {
        _recording = false;
        _videoFile = file;
      });
    }
  }

  Future<void> _flipCamera() async {
    if (cameras.length < 2 || _recording || _countdown != null) return;
    await _initCamera(_camIndex == 0 ? 1 : 0);
  }

  void _goToPreview() {
    if (_videoFile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          videoPath: _videoFile!.path,
          challengeTitle: widget.challengeTitle,
          challengeId: widget.challengeId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _timer?.cancel();
    _countdownTimer?.cancel();
    _cam?.dispose();
    _ghostCtrl?.dispose();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  String get _timeLabel {
    final m = _elapsed ~/ 60;
    final s = _elapsed % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _cam != null && _cam!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _cameraError
          ? _buildCameraError()
          : ready
              ? _buildCamera()
              : _buildLoading(),
    );
  }

  Widget _buildLoading() => const Center(
        child: CircularProgressIndicator(color: Color(0xFF7B2CBF)),
      );

  Widget _buildCameraError() {
    final title =
        _permissionDenied ? 'Camera access needed' : 'Camera unavailable';
    final message = _permissionDenied
        ? (_permissionPermanentlyDenied
            ? 'Camera and microphone access are turned off for Aura Arena. Go to Settings to enable them and record challenge videos.'
            : 'Aura Arena needs camera and microphone access to record challenge videos.')
        : 'Something went wrong starting the camera.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                _permissionDenied
                    ? Icons.no_photography_rounded
                    : Icons.videocam_off_rounded,
                color: Colors.white38,
                size: 52),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (_permissionPermanentlyDenied)
              ElevatedButton(
                onPressed: openAppSettings,
                style: ElevatedButton.styleFrom(backgroundColor: _purple),
                child: const Text('Open Settings'),
              )
            else
              TextButton(
                onPressed: () {
                  setState(() => _cameraError = false);
                  _initCamera(_camIndex);
                },
                child: Text(_permissionDenied ? 'Allow access' : 'Retry',
                    style: const TextStyle(color: Color(0xFF7B2CBF))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview ──────────────────────────────────────────────────
        // CameraPreview has no intrinsic size of its own — inside a
        // StackFit.expand Stack it simply stretches to fill whatever box
        // it's given, distorting the image whenever the sensor's aspect
        // ratio (previewSize, always reported in landscape orientation
        // regardless of device rotation) doesn't match the much taller
        // phone-screen aspect ratio. FittedBox+SizedBox at the true
        // (width/height swapped for portrait) preview size scale-crops
        // instead of stretching — same idiom already used for the ghost
        // overlay's VideoPlayer below.
        Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cam!.value.previewSize!.height,
              height: _cam!.value.previewSize!.width,
              child: CameraPreview(_cam!),
            ),
          ),
        ),

        // ── Ghost overlay — small PiP in bottom-right corner ───────────────
        // Always reserve the slot (not just once the video is ready) so the
        // reference clip never looks "missing" while it loads — a spinner
        // fills the box until playback is ready.
        if (widget.referenceVideoUrl.isNotEmpty && _ghostOn && !_ghostFailed)
          Positioned(
            right: 12,
            bottom: 148,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  border: Border.all(color: Colors.white30, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _ghostReady && _ghostCtrl != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _ghostCtrl!.value.size.width,
                          height: _ghostCtrl!.value.size.height,
                          child: VideoPlayer(_ghostCtrl!),
                        ),
                      )
                    : const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: _purple, strokeWidth: 2),
                        ),
                      ),
              ),
            ),
          ),

        // ── Top bar ─────────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _iconBtn(Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context)),
                const Spacer(),
                _iconBtn(Icons.flip_camera_ios_rounded,
                    onTap: (_recording || _countdown != null)
                        ? null
                        : _flipCamera),
              ],
            ),
          ),
        ),

        // ── Recording timer pill ─────────────────────────────────────────────
        if (_recording)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_graceRemaining != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Auto-stop in ${_graceRemaining}s',
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // ── Countdown overlay ───────────────────────────────────────────────
        // IgnorePointer lets the tap-to-cancel on the (still-visible, unchanged)
        // record button underneath keep working during the countdown.
        if (_countdown != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Text(
                      '$_countdown',
                      key: ValueKey(_countdown),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 110,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 24, color: Colors.black87)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Bottom controls ──────────────────────────────────────────────────
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 76,
              child: Stack(
                children: [
                  // Record button (+ Preview/Retake either side of it) is
                  // always the one thing kept truly centered on screen —
                  // Timer/Ghost are pinned to the edges independently below,
                  // so neither one's width can push the record button off
                  // center or collide with the other.
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Preview button (shown after recording)
                        if (_videoFile != null && !_recording)
                          _circleBtn(
                            icon: Icons.play_arrow_rounded,
                            size: 48,
                            color: Colors.white24,
                            onTap: _goToPreview,
                            label: 'Preview',
                          ),

                        if (_videoFile != null && !_recording)
                          const SizedBox(width: 24),

                        // Record button
                        GestureDetector(
                          key: const Key('recordButton'),
                          onTap: _toggleRecord,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 3),
                              color: _recording
                                  ? Colors.red
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: _recording ? 24 : 54,
                                height: _recording ? 24 : 54,
                                decoration: BoxDecoration(
                                  color:
                                      _recording ? Colors.red : Colors.white,
                                  borderRadius: BorderRadius.circular(
                                      _recording ? 6 : 54),
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (_videoFile != null && !_recording)
                          const SizedBox(width: 24),

                        // Retake / placeholder
                        if (_videoFile != null && !_recording)
                          _circleBtn(
                            icon: Icons.refresh_rounded,
                            size: 48,
                            color: Colors.white24,
                            onTap: () => setState(() => _videoFile = null),
                            label: 'Retake',
                          ),
                      ],
                    ),
                  ),

                  // Timer toggle — pinned to the left edge, independent of
                  // the record-button row.
                  if (!_recording && _videoFile == null)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _pillToggle(
                          icon: Icons.timer_outlined,
                          label: _timerSeconds > 0
                              ? 'Timer ${_timerSeconds}s'
                              : 'Timer Off',
                          active: _timerSeconds > 0,
                          onTap: _countdown != null ? null : _cycleTimer,
                        ),
                      ),
                    ),

                  // Ghost toggle — pinned to the right edge, independent of
                  // the record-button row.
                  if (widget.referenceVideoUrl.isNotEmpty &&
                      !_recording &&
                      _videoFile == null)
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _pillToggle(
                          icon: _ghostFailed
                              ? Icons.visibility_off_rounded
                              : _ghostOn
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                          label: _ghostFailed
                              ? 'Ghost unavailable'
                              : 'Ghost ${_ghostOn ? 'ON' : 'OFF'}',
                          active: !_ghostFailed && _ghostOn,
                          faded: _ghostFailed,
                          onTap: _ghostFailed
                              ? null
                              : () => setState(() => _ghostOn = !_ghostOn),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillToggle({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
    bool faded = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _purple.withValues(alpha: 0.30) : Colors.black45,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: faded
                  ? Colors.white24
                  : active
                      ? _purple
                      : Colors.white30,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: faded ? Colors.white38 : Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: faded ? AppColors.textFaint : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _iconBtn(IconData icon, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: onTap != null ? Colors.white : Colors.white38, size: 20),
        ),
      );

  Widget _circleBtn({
    required IconData icon,
    required double size,
    required Color color,
    required VoidCallback onTap,
    required String label,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: size * 0.45),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
          ],
        ),
      );
}
