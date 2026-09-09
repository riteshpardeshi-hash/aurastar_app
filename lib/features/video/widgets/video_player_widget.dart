import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/video_prewarm_cache.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String url;

  /// Pre-generated thumbnail shown while the video buffers.
  final String? thumbnailUrl;

  /// For clips recorded by this app's own portrait-locked camera (the user's
  /// own submissions), size the layout box from [portraitPreviewAspectRatio]
  /// instead of trusting `rotationCorrection` — that metadata is unreliable
  /// for locally-recorded files and otherwise squeezes a portrait recording
  /// into a short, wide, letterboxed strip. Leave false for arbitrary remote
  /// videos (reels, challenge reference clips) that may genuinely be landscape.
  final bool forcePortrait;

  const VideoPlayerWidget(
    this.url, {
    super.key,
    this.thumbnailUrl,
    this.forcePortrait = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // A caller that already knew this video was likely to be opened next
    // (a list screen calling VideoPrewarmCache.prewarm ahead of the tap
    // that lands here) may have already built and initialized this exact
    // controller in the background — reuse it instead of starting a cold
    // load, so playback can begin immediately.
    final prewarmed = VideoPrewarmCache.take(widget.url);
    if (prewarmed != null) {
      _ctrl = prewarmed;
      _ready = true;
      _ctrl.play();
      return;
    }
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    )..initialize().then((_) {
        if (mounted) {
          setState(() => _ready = true);
          _ctrl.play();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Opaque base so any letterbox margin around a `contain`-fitted video
        // reads as a clean bar, not a glimpse of the cover-scaled thumbnail
        // underneath (which looks like a zoomed-in copy of the video itself).
        const ColoredBox(color: Colors.black),
        // Poster frame, only while the video is still loading — once it's
        // playing the cover-scaled thumbnail would otherwise peek out past
        // the edges of the aspect-fitted VideoPlayer.
        if (!_ready)
          VideoThumbnailWidget(
            videoUrl: widget.url,
            thumbnailUrl: widget.thumbnailUrl,
            fit: BoxFit.cover,
          ),
        if (_ready)
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.forcePortrait
                    ? portraitPreviewAspectRatio(_ctrl.value)
                    : correctedVideoAspectRatio(_ctrl.value),
                child: VideoPlayer(_ctrl),
              ),
            ),
          ),
        if (!_ready)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Color(0xFF7B2CBF),
                strokeWidth: 2.5,
              ),
            ),
          ),
      ],
    );
  }
}
