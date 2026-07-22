import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/upload_queue_service.dart';
import '../../challenges/widgets/aura_submitted_popup.dart';
import '../../challenges/widgets/aura_sense_loading_view.dart';
import '../../challenges/screens/post_score_action_screen.dart';
import '../../account/screens/settings_screen.dart';
import '../../dashboard/dashboard.dart';

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
  // Guards against the auto-retry timer and a manual "Retry Upload" tap
  // both calling _upload() at once: the auto-retry branch awaits
  // hasInternet() before flipping state out of `failed`, and during that
  // gap the Retry button is still visible and tappable. Without this,
  // two concurrent runs could each presign + upload + create a submission
  // (a duplicate), and whichever finished last would clobber
  // _uploadState — so a successful run could get overwritten back to
  // `failed`, leaving the user stuck on an error despite the upload
  // having actually gone through.
  bool _uploadInFlight = false;

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
    if (_uploadInFlight) return;
    _uploadInFlight = true;
    try {
      await _doUpload(isAutoRetry: isAutoRetry);
    } finally {
      _uploadInFlight = false;
    }
  }

  Future<void> _doUpload({bool isAutoRetry = false}) async {
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

      // Step 1: get presigned S3 URL + claim an unclaimed Video placeholder
      final presign = await service.presignSubmission(widget.challengeId);
      final uploadUrl = presign['uploadUrl'] as String;
      final videoId = presign['videoId'] as String;

      // Step 2: upload directly to S3
      await ApiClient().uploadToS3(
        uploadUrl,
        File(widget.videoPath),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p * 0.9);
        },
      );

      // Step 3: create submission record + get AI score — claims the
      // presigned Video placeholder by videoId (ADR 036), not by S3 key.
      // This call runs content-safety, face verification, and rubric
      // scoring synchronously server-side and can legitimately take up to
      // _scoringTimeout (90s) — swap to the full-screen "Aura Sense"
      // animation for this wait instead of leaving the progress bar frozen
      // at 95% with no explanation of what's happening.
      if (mounted) {
        setState(() => _uploadState = _UploadState.scoring);
        _player.pause();
      }
      final submission =
          await service.createSubmission(widget.challengeId, videoId);

      await UploadQueueService.clear();

      if (!mounted) return;
      setState(() => _uploadState = _UploadState.done);

      final submissionId = submission['_id'] as String? ?? '';

      final action = await showDialog<String>(
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
      if (action == 'retry') {
        // CameraScreen pushed this screen (not a replacement), so it's
        // still alive underneath — pop back to it for another take of the
        // same challenge instead of pushing a fresh camera session.
        Navigator.of(context).pop();
        return;
      }
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
      // A dropped/stalled connection can surface as any of these — not just
      // SocketException — depending on which step (presign, S3 PUT, or
      // create-submission) it hit. Misclassifying it as a server error meant
      // showing the raw exception string with no auto-retry instead of the
      // friendly "we'll retry automatically" flow.
      final isNetworkError =
          e is SocketException || e is TimeoutException || e is http.ClientException;
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

  // The backend rejects uploads with this message when the user's profile
  // is missing country/city/interests — a distinct fix (finish onboarding),
  // not something a plain retry will resolve.
  bool get _isProfileIncomplete {
    final text = (_lastError ?? '').toLowerCase();
    return text.contains('onboarding') ||
        (text.contains('profile') && text.contains('complete'));
  }

  // The backend rejects the submission with this message when the challenge
  // itself was never assigned a scoring rubric (an admin/data setup gap) —
  // nothing to do with the recorded video, and retrying just fails the same
  // way again since there's nothing on the client to fix.
  bool get _isMissingRubric {
    final text = (_lastError ?? '').toLowerCase();
    return text.contains('no scoring rubric');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  void _giveUpOnScoring() {
    // The scoring request keeps running server-side regardless — _doUpload's
    // `if (!mounted) return;` guards make it safe to abandon here and let
    // the result show up next time the user checks their profile.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uploadState == _UploadState.scoring) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: AuraSenseLoadingView(onGiveUp: _giveUpOnScoring),
      );
    }
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
      // build() returns the full-screen AuraSenseLoadingView before ever
      // reaching _buildBottom() for this state.
      case _UploadState.scoring:
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
                    _isMissingRubric
                        ? Icons.rule_folder_outlined
                        : _isNetworkError
                            ? Icons.wifi_off_rounded
                            : Icons.error_outline_rounded,
                    color: _isMissingRubric ? Colors.amber : Colors.redAccent,
                    size: 18),
                const SizedBox(width: 8),
                Text(_isMissingRubric ? 'Challenge not ready' : 'Upload failed',
                    style: TextStyle(
                        color: _isMissingRubric ? Colors.amber : Colors.redAccent,
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
              _isMissingRubric
                  ? 'This challenge hasn\'t been set up for scoring yet. Your video wasn\'t the problem — please try a different challenge instead.'
                  : _isNetworkError
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
                    onTap: _isProfileIncomplete
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            )
                        // A missing rubric is a challenge-setup problem, not
                        // something a retry can fix — send the user back
                        // instead of re-running the same failing upload.
                        : _isMissingRubric
                            ? () => Navigator.pop(context)
                            : _upload,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isMissingRubric ? Colors.amber : Colors.redAccent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (_isMissingRubric
                                    ? Colors.amber
                                    : Colors.redAccent)
                                .withValues(alpha: 0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                            _isProfileIncomplete
                                ? 'Complete Your Profile'
                                : _isMissingRubric
                                    ? 'Choose Another Challenge'
                                    : 'Retry Upload',
                            style: TextStyle(
                                color: _isMissingRubric
                                    ? Colors.black87
                                    : Colors.white,
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

enum _UploadState { idle, uploading, scoring, failed, done }
