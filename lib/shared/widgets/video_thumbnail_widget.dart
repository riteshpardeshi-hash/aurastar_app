import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Shared in-memory cache — keyed by video URL, value is extracted JPEG bytes.
/// Accessible by dashboard's private widget so the two never re-extract the same video.
final Map<String, Uint8List> videoThumbnailCache = {};

class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;

  /// Pre-generated thumbnail stored in Firestore. When non-null the widget
  /// loads instantly via Image.network instead of extracting from the video.
  final String? thumbnailUrl;

  final BoxFit fit;

  const VideoThumbnailWidget({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _useNetwork = false;

  static const _gradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1A0533), Color(0xFF2D1B69)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoThumbnailWidget old) {
    super.didUpdateWidget(old);
    if (old.videoUrl != widget.videoUrl ||
        old.thumbnailUrl != widget.thumbnailUrl) {
      setState(() {
        _loading = true;
        _bytes = null;
        _useNetwork = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    // Fast path — use stored thumbnail URL (Image.network is instant)
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      if (mounted) setState(() { _useNetwork = true; _loading = false; });
      return;
    }

    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // In-memory cache hit
    if (videoThumbnailCache.containsKey(widget.videoUrl)) {
      if (mounted) {
        setState(() {
          _bytes = videoThumbnailCache[widget.videoUrl];
          _loading = false;
        });
      }
      return;
    }

    // HLS manifests (.m3u8) can't be frame-extracted by video_thumbnail — it
    // expects a direct video file. Skip straight to the fallback icon instead
    // of wasting a 12s timeout per card.
    if (_isHlsUrl(widget.videoUrl)) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Slow path — extract frame from video (downloads the file). The
    // video_thumbnail plugin has no partial/byte-range fetch, so it always
    // pulls the whole clip before it can decode a frame; 12s was too tight
    // for a several-MB submission on a real mobile connection and was the
    // main cause of thumbnails silently falling back to the placeholder.
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
        timeMs: 500,
      ).timeout(const Duration(seconds: 30));
      debugPrint('[VideoThumbnail] ${widget.videoUrl} -> ${data == null ? "null (no frame extracted)" : "${data.length} bytes"}');
      if (data != null) videoThumbnailCache[widget.videoUrl] = data;
      if (mounted) setState(() { _bytes = data; _loading = false; });
    } catch (e, st) {
      debugPrint('[VideoThumbnail] FAILED for ${widget.videoUrl}: $e');
      debugPrint('$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const VideoThumbnailSkeleton();

    if (_useNetwork) {
      return Image.network(
        widget.thumbnailUrl!,
        fit: widget.fit,
        cacheWidth: 480,
        errorBuilder: (_, __, ___) => _fallback(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const VideoThumbnailSkeleton(),
      );
    }

    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit, gaplessPlayback: true);
    }

    return _fallback();
  }

  Widget _fallback() => Container(
        decoration: _gradient,
        child: const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white24, size: 32),
        ),
      );
}

bool _isHlsUrl(String url) => url.toLowerCase().contains('.m3u8');

/// Animated shimmer shown while the thumbnail is loading.
class VideoThumbnailSkeleton extends StatefulWidget {
  const VideoThumbnailSkeleton({super.key});

  @override
  State<VideoThumbnailSkeleton> createState() => _VideoThumbnailSkeletonState();
}

class _VideoThumbnailSkeletonState extends State<VideoThumbnailSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                  const Color(0xFF1A0533), const Color(0xFF3D1166), _anim.value)!,
              Color.lerp(
                  const Color(0xFF2D1B69), const Color(0xFF4A2D9E), _anim.value)!,
            ],
          ),
        ),
      ),
    );
  }
}
