import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lets the creator watch their reference video before submitting — the file
/// they just recorded/picked, or the uploaded one when editing. Starts paused;
/// tap to play or pause. Loops.
class ReferenceVideoPreview extends StatefulWidget {
  final File? file;
  final String? url;
  final double maxHeight;

  const ReferenceVideoPreview({super.key, this.file, this.url, this.maxHeight = 380})
      : assert(file != null || url != null);

  @override
  State<ReferenceVideoPreview> createState() => _ReferenceVideoPreviewState();
}

class _ReferenceVideoPreviewState extends State<ReferenceVideoPreview> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(ReferenceVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file?.path != widget.file?.path || oldWidget.url != widget.url) {
      _ctrl?.dispose();
      _ctrl = null;
      _ready = false;
      _failed = false;
      _init();
    }
  }

  void _init() {
    final ctrl = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _ctrl = ctrl;
    ctrl.setLooping(true);
    ctrl.initialize().then((_) {
      if (mounted && _ctrl == ctrl) setState(() => _ready = true);
    }).catchError((Object _) {
      if (mounted && _ctrl == ctrl) setState(() => _failed = true);
    });
    ctrl.addListener(_onTick);
  }

  bool _wasPlaying = false;
  void _onTick() {
    final playing = _ctrl?.value.isPlaying ?? false;
    if (playing != _wasPlaying && mounted) setState(() => _wasPlaying = playing);
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null || !_ready) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final aspect = _ready && c != null && c.value.aspectRatio > 0 ? c.value.aspectRatio : 9 / 16;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: GestureDetector(
              key: const Key('reference-video-preview'),
              onTap: _toggle,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_ready && c != null) VideoPlayer(c),
                    if (_failed)
                      const Center(
                        child: Text('Couldn\'t play this video',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                      )
                    else if (!_ready)
                      const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                        ),
                      )
                    else if (!_wasPlaying)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
