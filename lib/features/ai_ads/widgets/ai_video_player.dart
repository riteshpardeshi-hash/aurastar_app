import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'ai_ui.dart';

/// Tap-to-play preview of a generated / finished ad. The video only loads
/// when tapped, so lists stay light.
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

  Future<void> _start() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() => _controller = c);
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

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
                onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                child: VideoPlayer(c),
              ),
      ),
    );
  }
}
