import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

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

  /// Returns true if the device can currently reach Aura's own backend —
  /// the only reachability signal that actually matters for deciding
  /// whether an upload retry will succeed.
  ///
  /// This used to be a DNS lookup of Google's public DNS server (8.8.8.8)
  /// with a 4s timeout. That tested something unrelated to the app: some
  /// Wi-Fi/carrier networks (captive portals, corporate firewalls) block or
  /// throttle direct traffic to that specific address while Aura's own API
  /// is perfectly reachable — a false "offline" on a genuinely connected
  /// device. The reverse also happens: Google's DNS is up but Aura's
  /// single-VPS backend is briefly down (redeploy, restart), which the old
  /// check couldn't detect at all since a numeric address like 8.8.8.8 is
  /// answered locally by most platforms' resolvers without any real network
  /// round trip — so it would often report "online" even with no working
  /// connection. Testing a real TCP connect to the backend itself answers
  /// the actual question instead of guessing at it via a third party.
  static Future<bool> hasInternet() async {
    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final socket = await Socket.connect(
        uri.host,
        uri.hasPort ? uri.port : 80,
        timeout: const Duration(seconds: 8),
      );
      socket.destroy();
      return true;
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
