import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/upload_queue_service.dart';
import '../../challenges/widgets/aura_submitted_popup.dart';
import '../../challenges/screens/post_score_action_screen.dart';

class PreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;
  final String challengeId;

  const PreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
    required this.challengeId,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  static const _purple = Color(0xFF7B2CBF);

  late VideoPlayerController _player;
  bool _playerReady = false;
  bool _isPlaying = false;

  // Upload state
  _UploadState _uploadState = _UploadState.idle;
  double _progress = 0; // 0.0 – 1.0
  Timer? _retryTimer;
  int _retryIntervalSeconds = 5;
  String? _lastError;
  bool _isNetworkError = false;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _playerReady = true);
        _player.play();
        _player.setLooping(true);
        setState(() => _isPlaying = true);
      });
    _player.addListener(() {
      if (mounted) setState(() => _isPlaying = _player.value.isPlaying);
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Upload ──────────────────────────────────────────────────────────────────

  void _startAutoRetry() {
    _retryTimer?.cancel();
    _retryIntervalSeconds = 5;
    _retryTimer = Timer.periodic(
      Duration(seconds: _retryIntervalSeconds),
      (_) async {
        if (_uploadState != _UploadState.failed) {
          _retryTimer?.cancel();
          return;
        }
        final online = await UploadQueueService.hasInternet();
        if (online && mounted && _uploadState == _UploadState.failed) {
          _retryTimer?.cancel();
          _upload(isAutoRetry: true);
        } else {
          // Exponential backoff: 5 → 10 → 20 → 30s cap
          _retryIntervalSeconds = (_retryIntervalSeconds * 2).clamp(5, 30);
          _retryTimer?.cancel();
          _startAutoRetry();
        }
      },
    );
  }

  Future<void> _upload({bool isAutoRetry = false}) async {
    final online = await UploadQueueService.hasInternet();
    if (!online) {
      if (!mounted) return;
      setState(() {
        _uploadState = _UploadState.failed;
        _isNetworkError = true;
        _lastError = null;
      });
      await UploadQueueService.save(
        videoPath: widget.videoPath,
        challengeId: widget.challengeId,
        challengeTitle: widget.challengeTitle,
      );
      _startAutoRetry();
      if (!isAutoRetry && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No internet. We\'ll retry automatically when you\'re back online.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    _retryTimer?.cancel();
    setState(() {
      _uploadState = _UploadState.uploading;
      _progress = 0;
    });

    try {
      final service = ChallengesService();

      // Step 1: get presigned S3 URL
      final presign = await service.presignSubmission(widget.challengeId);
      final uploadUrl = presign['uploadUrl'] as String;
      final videoKey = presign['key'] as String;

      // Step 2: upload directly to S3
      await ApiClient().uploadToS3(
        uploadUrl,
        File(widget.videoPath),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p * 0.9);
        },
      );

      // Step 3: create submission record + get AI score
      if (mounted) setState(() => _progress = 0.95);
      final submission =
          await service.createSubmission(widget.challengeId, videoKey);

      await UploadQueueService.clear();

      if (!mounted) return;
      setState(() => _uploadState = _UploadState.done);
      _player.pause();

      final submissionId = submission['_id'] as String? ?? '';

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (_) => AuraSubmittedPopup(
          submissionId: submissionId,
          challengeTitle: widget.challengeTitle,
          challengeId: widget.challengeId,
          initialResult: submission,
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PostScoreActionScreen(
            submissionId: submissionId,
            challengeTitle: widget.challengeTitle,
            challengeId: widget.challengeId,
            submissionData: submission,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[Upload] failed: $e\n$st');
      if (!mounted) return;
      final isNetworkError = e is SocketException;
      setState(() {
        _uploadState = _UploadState.failed;
        _isNetworkError = isNetworkError;
        _lastError = _describeError(e);
      });
      await UploadQueueService.save(
        videoPath: widget.videoPath,
        challengeId: widget.challengeId,
        challengeTitle: widget.challengeTitle,
      );
      // Only auto-retry connectivity failures — server-rejected requests
      // (e.g. incomplete profile) will just fail the same way again.
      if (isNetworkError) _startAutoRetry();
    }
  }

  String _describeError(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _uploadState == _UploadState.uploading
                        ? null
                        : () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
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
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Video preview
            Expanded(
              child: _playerReady
                  ? GestureDetector(
                      onTap: () {
                        _isPlaying ? _player.pause() : _player.play();
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _player.value.aspectRatio,
                            child: VideoPlayer(_player),
                          ),
                          if (!_isPlaying)
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.50),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 30),
                            ),
                        ],
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: _purple)),
            ),

            // Bottom section
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottom() {
    switch (_uploadState) {
      case _UploadState.idle:
        return _idleControls();
      case _UploadState.uploading:
        return _uploadingView();
      case _UploadState.failed:
        return _failedView();
      case _UploadState.done:
        return const SizedBox.shrink();
    }
  }

  // Idle — Submit / Retake buttons
  Widget _idleControls() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Looks good?',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Center(
                        child: Text('Retake',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _upload,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _purple,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _purple.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text('Submit for Aura Score',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // Uploading — progress bar with %
  Widget _uploadingView() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploading…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: _purple,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(_purple),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep app open • Failed upload = no attempt lost',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
          ],
        ),
      );

  // Failed — retry button, local file preserved. Auto-retry only applies
  // to connectivity failures; server-rejected requests show the real reason.
  Widget _failedView() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    _isNetworkError
                        ? Icons.wifi_off_rounded
                        : Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    size: 18),
                const SizedBox(width: 8),
                const Text('Upload failed',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                if (_isNetworkError) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.35)),
                    ),
                    child: const Text('Auto-retry on',
                        style: TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _isNetworkError
                  ? 'Your video is saved. We\'ll retry automatically when you\'re back online.'
                  : (_lastError ??
                      'Something went wrong. Please try again.'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
            ),
            if (_isNetworkError && _lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                _lastError!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30), fontSize: 10),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Center(
                        child: Text('Retake',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _upload,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text('Retry Upload',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

enum _UploadState { idle, uploading, failed, done }
