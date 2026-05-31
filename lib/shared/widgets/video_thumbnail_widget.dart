import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;

  const VideoThumbnailWidget({
    super.key,
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  Uint8List? _bytes;
  bool _loading = true;

  static const _fallback = BoxDecoration(
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

  Future<void> _load() async {
    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 80,
      );
      if (mounted) setState(() { _bytes = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        decoration: _fallback,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: Color(0xFF7B2CBF), strokeWidth: 2),
          ),
        ),
      );
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit);
    }
    return Container(
      decoration: _fallback,
      child: const Center(
        child: Icon(Icons.play_circle_outline_rounded,
            color: Colors.white24, size: 32),
      ),
    );
  }
}
