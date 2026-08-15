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
  static const _maxSeconds = 15;

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
    _ghostCtrl!.setLooping(true);
    // Muted: this is a visual overlay guide only — its audio must not bleed
    // into the mic recording of the user's own take.
    await _ghostCtrl!.setVolume(0.0);
    setState(() => _ghostReady = true);
  }

  Future<void> _toggleRecord() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      _elapsed++;
      setState(() {});
      if (_elapsed >= _maxSeconds) await _stopRecording();
    });
    setState(() {
      _recording = true;
      _videoFile = null;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
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
    if (cameras.length < 2 || _recording) return;
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
    _cam?.dispose();
    _ghostCtrl?.dispose();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  String get _timeLabel {
    final remaining = _maxSeconds - _elapsed;
    return '${remaining}s';
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.challengeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                ),
                _iconBtn(Icons.flip_camera_ios_rounded,
                    onTap: _recording ? null : _flipCamera),
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
                      '$_timeLabel left',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_elapsed}s',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Progress bar (bottom of screen while recording) ─────────────────
        if (_recording)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _elapsed / _maxSeconds,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(_purple),
              minHeight: 3,
            ),
          ),

        // ── Bottom controls ──────────────────────────────────────────────────
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ghost toggle
                if (widget.referenceVideoUrl.isNotEmpty && !_recording)
                  GestureDetector(
                    onTap: _ghostFailed
                        ? null
                        : () => setState(() => _ghostOn = !_ghostOn),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _ghostFailed
                            ? Colors.black45
                            : _ghostOn
                                ? _purple.withValues(alpha: 0.30)
                                : Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _ghostFailed
                              ? Colors.white24
                              : _ghostOn
                                  ? _purple
                                  : Colors.white30,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _ghostFailed
                                ? Icons.visibility_off_rounded
                                : _ghostOn
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                            color: _ghostFailed ? Colors.white38 : Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _ghostFailed
                                ? 'Ghost unavailable'
                                : 'Ghost ${_ghostOn ? 'ON' : 'OFF'}',
                            style: TextStyle(
                              color: _ghostFailed ? AppColors.textFaint : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                          border: Border.all(color: Colors.white, width: 3),
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
                              color: _recording ? Colors.red : Colors.white,
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

                const SizedBox(height: 12),
                Text(
                  _recording
                      ? 'Copy the move as closely as you can'
                      : _videoFile != null
                          ? 'Tap Preview to review your video'
                          : 'Hold to record • 15 seconds max',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

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
