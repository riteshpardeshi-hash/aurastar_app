import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import '../../../core/globals.dart';
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

  // Ghost overlay
  VideoPlayerController? _ghostCtrl;
  bool _ghostOn = true;
  bool _ghostReady = false;

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
    _cam?.dispose();
    _cam = CameraController(cameras[index], ResolutionPreset.high,
        enableAudio: true);
    try {
      await _cam!.initialize();
    } catch (_) {
      if (mounted) setState(() { _cam = null; _cameraError = true; });
      return;
    }
    if (!mounted) return;
    setState(() { _camIndex = index; _cameraError = false; });
  }

  Future<void> _initGhost() async {
    _ghostCtrl =
        VideoPlayerController.networkUrl(Uri.parse(widget.referenceVideoUrl));
    try {
      await _ghostCtrl!.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _ghostCtrl!.setLooping(true);
    _ghostCtrl!.setVolume(0);
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
    _ghostCtrl?.play();
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

  Widget _buildCameraError() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 52),
            const SizedBox(height: 12),
            const Text('Camera unavailable',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () { setState(() => _cameraError = false); _initCamera(_camIndex); },
              child: const Text('Retry', style: TextStyle(color: Color(0xFF7B2CBF))),
            ),
          ],
        ),
      );

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview ──────────────────────────────────────────────────
        CameraPreview(_cam!),

        // ── Ghost overlay — small PiP in bottom-right corner ───────────────
        if (_ghostReady && _ghostOn && _ghostCtrl != null)
          Positioned(
            right: 12,
            bottom: 148,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ghostCtrl!.value.size.width,
                    height: _ghostCtrl!.value.size.height,
                    child: VideoPlayer(_ghostCtrl!),
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
                    onTap: () => setState(() => _ghostOn = !_ghostOn),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _ghostOn
                            ? _purple.withValues(alpha: 0.30)
                            : Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _ghostOn ? _purple : Colors.white30,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _ghostOn
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Ghost ${_ghostOn ? 'ON' : 'OFF'}',
                            style: const TextStyle(
                              color: Colors.white,
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
