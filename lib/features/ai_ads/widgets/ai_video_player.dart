import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'ai_ui.dart';

/// A generated / finished ad with real controls. The video only loads when tapped (lists
/// stay light), plays **once** and stops on a Replay button — never loops. Play / pause,
/// a seek bar with the time, and mute; the controls fade while it plays and come back on tap.
class AiVideoPlayer extends StatefulWidget {
  final String url;
  final double aspectRatio;

  const AiVideoPlayer({super.key, required this.url, this.aspectRatio = 9 / 16});

  @override
  State<AiVideoPlayer> createState() => _AiVideoPlayerState();
}

class _AiVideoPlayerState extends State<AiVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  Future<void> _start() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() => _controller = c);
    try {
      await c.initialize();
      await c.setLooping(false);
      c.addListener(_onTick);
      await c.play();
      _scheduleHide();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (!mounted) return;
    // Rebuild for the time label / play state; show the controls again when it ends.
    if (_ended && !_controlsVisible) _controlsVisible = true;
    // Started playing after buffering with the controls up — fade them out as usual.
    if (_controlsVisible && (_controller?.value.isPlaying ?? false) && !(_hideTimer?.isActive ?? false)) _scheduleHide();
    setState(() {});
  }

  bool get _ended {
    final v = _controller?.value;
    if (v == null || !v.isInitialized || v.duration == Duration.zero) return false;
    return !v.isPlaying && v.position >= v.duration - const Duration(milliseconds: 200);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    if (_ended) {
      await c.seekTo(Duration.zero);
      await c.play();
    } else if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    c.setVolume(c.value.volume > 0 ? 0 : 1);
    _scheduleHide();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return AspectRatio(
      aspectRatio: c != null && c.value.isInitialized ? c.value.aspectRatio : widget.aspectRatio,
      child: Container(
        decoration: AiUi.cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: _failed
            ? const Center(child: Text("Couldn't play this video", style: TextStyle(color: Colors.white54)))
            : c == null
            ? InkWell(
                key: const Key('ai-video-play'),
                onTap: _start,
                child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 56)),
              )
            : !c.value.isInitialized
            ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
            : GestureDetector(
                onTap: _showControls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(c),
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(ignoring: !_controlsVisible, child: _controls(c)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _controls(VideoPlayerController c) {
    final v = c.value;
    final ended = _ended;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.transparent, Color(0xB3000000)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: GestureDetector(
              key: const Key('ai-video-toggle'),
              onTap: _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: Icon(
                  ended
                      ? Icons.replay_rounded
                      : v.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: Key(ended ? 'ai-video-replay' : v.isPlaying ? 'ai-video-pause' : 'ai-video-resume'),
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 4,
            bottom: 6,
            child: Row(
              children: [
                Text(
                  '${_clock(v.position)} / ${_clock(v.duration)}',
                  key: const Key('ai-video-time'),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    colors: VideoProgressColors(
                      playedColor: AiUi.accent,
                      bufferedColor: Colors.white.withValues(alpha: 0.35),
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('ai-video-mute'),
                  onPressed: _toggleMute,
                  icon: Icon(v.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
