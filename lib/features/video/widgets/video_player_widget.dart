import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/utils/video_aspect_ratio.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String url;

  /// Pre-generated thumbnail shown while the video buffers.
  final String? thumbnailUrl;

  const VideoPlayerWidget(this.url, {super.key, this.thumbnailUrl});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
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
        // Thumbnail visible until video is ready
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
                aspectRatio: correctedVideoAspectRatio(_ctrl.value),
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
