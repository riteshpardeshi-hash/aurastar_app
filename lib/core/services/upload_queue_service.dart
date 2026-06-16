import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a single pending video upload across app restarts.
/// Only one pending upload is tracked at a time — the most recent failed one.
class UploadQueueService {
  static const _keyVideoPath      = 'uq_video_path';
  static const _keyChallengId     = 'uq_challenge_id';
  static const _keyChallengeTitle = 'uq_challenge_title';

  static Future<void> save({
    required String videoPath,
    required String challengeId,
    required String challengeTitle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoPath,      videoPath);
    await prefs.setString(_keyChallengId,     challengeId);
    await prefs.setString(_keyChallengeTitle, challengeTitle);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyVideoPath);
    await prefs.remove(_keyChallengId);
    await prefs.remove(_keyChallengeTitle);
  }

  /// Returns null if nothing is queued or the file no longer exists on disk.
  static Future<PendingUpload?> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    final videoPath      = prefs.getString(_keyVideoPath);
    final challengeId    = prefs.getString(_keyChallengId);
    final challengeTitle = prefs.getString(_keyChallengeTitle);
    if (videoPath == null || challengeId == null || challengeTitle == null) {
      return null;
    }
    // Silently discard if the file was cleaned up by the OS.
    if (!File(videoPath).existsSync()) {
      await clear();
      return null;
    }
    return PendingUpload(
      videoPath:      videoPath,
      challengeId:    challengeId,
      challengeTitle: challengeTitle,
    );
  }

  static Future<bool> hasPending() async => (await getPending()) != null;

  /// Returns true if the device can reach the internet.
  static Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('8.8.8.8')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

class PendingUpload {
  final String videoPath;
  final String challengeId;
  final String challengeTitle;

  const PendingUpload({
    required this.videoPath,
    required this.challengeId,
    required this.challengeTitle,
  });
}
