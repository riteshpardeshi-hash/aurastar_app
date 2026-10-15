import 'dart:io';

/// What a [ChallengeCreateFlow.run] ended with.
enum ChallengeCreateOutcome {
  /// The create request answered with the new challenge.
  created,

  /// An earlier attempt's create request reached the server but its answer was lost (a
  /// timeout or a dropped connection). Retrying with the same video got "already claimed",
  /// which means that earlier attempt created the challenge.
  createdEarlier,
}

/// Uploaded reference video ready to be claimed by a create request.
class ChallengeVideoUpload {
  final String uploadUrl;
  final String videoId;
  const ChallengeVideoUpload({required this.uploadUrl, required this.videoId});
}

/// Presign → upload → create for a new challenge, safe to retry.
///
/// Creating a challenge runs a slow AI check on the reference video server-side, so the
/// create request can outlive the connection: the server creates the challenge, the app
/// sees an error. A naive retry re-uploads and creates a duplicate (seen in production on
/// 2026-10-15). This flow keeps the uploaded video across retries — the server lets a video
/// be claimed by exactly one challenge — and treats "already claimed" after an earlier
/// create attempt as "that attempt worked".
///
/// One instance per form; call [reset] when the user picks a different video.
class ChallengeCreateFlow {
  final Future<ChallengeVideoUpload> Function() presign;
  final Future<void> Function(String uploadUrl, File video, void Function(double progress) onProgress) upload;
  final Future<void> Function(String videoId) create;

  ChallengeCreateFlow({required this.presign, required this.upload, required this.create});

  String? _videoId;
  String? _videoPath;
  bool _createAttempted = false;

  /// The step in flight, for `Couldn't $step` messages: 'request the video upload',
  /// 'upload the reference video' or 'create the challenge'.
  String step = '';

  /// True once [video] is uploaded and only the create request is left to (re)try.
  bool isUploaded(File video) => _videoId != null && _videoPath == video.path;

  void reset() {
    _videoId = null;
    _videoPath = null;
    _createAttempted = false;
  }

  Future<ChallengeCreateOutcome> run(
    File video, {
    void Function(String step)? onStep,
    void Function(double progress)? onUploadProgress,
  }) async {
    if (!isUploaded(video)) {
      reset();
      step = 'request the video upload';
      onStep?.call(step);
      final target = await presign();
      step = 'upload the reference video';
      onStep?.call(step);
      await upload(target.uploadUrl, video, onUploadProgress ?? (_) {});
      _videoId = target.videoId;
      _videoPath = video.path;
    }

    step = 'create the challenge';
    onStep?.call(step);
    final retrying = _createAttempted;
    _createAttempted = true;
    try {
      await create(_videoId!);
    } catch (e) {
      if (retrying && isAlreadyClaimed(e)) {
        reset();
        return ChallengeCreateOutcome.createdEarlier;
      }
      rethrow;
    }
    reset();
    return ChallengeCreateOutcome.created;
  }

  /// The backend's 409 when a video already belongs to a challenge
  /// (`challenges.service.js` / `creatorChallenge.service.js`).
  static bool isAlreadyClaimed(Object error) => error.toString().toLowerCase().contains('already been claimed');
}
