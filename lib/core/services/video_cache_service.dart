import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks recently viewed videos and caches their bytes to disk so a video
/// that's known ahead of time (e.g. a challenge's reference clip, prefetched
/// while the user is still reading the challenge/rules) can play back
/// instantly from a local file instead of streaming over the network.
class VideoCacheService {
  VideoCacheService._();

  static const _recentKey = 'recently_viewed_videos';
  static const _maxEntries = 20;
  static const _downloadTimeout = Duration(seconds: 45);

  // Dedupes concurrent ensureCached() calls for the same URL (e.g. a
  // ChallengeDetail prefetch racing CameraScreen's own request) so they
  // share one download instead of writing the same file twice.
  static final Map<String, Future<String?>> _inFlight = {};

  static Future<void> markViewed(String videoUrl) async {
    if (videoUrl.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? [];
    list.remove(videoUrl);
    list.insert(0, videoUrl);
    if (list.length > _maxEntries) list.length = _maxEntries;
    await prefs.setStringList(_recentKey, list);
  }

  static Future<List<String>> recentlyViewed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? [];
  }

  /// Downloads [videoUrl] to a local cache file if it isn't already cached,
  /// and returns the local file path. Safe to call speculatively and more
  /// than once for the same URL — a later call reuses the in-flight download
  /// or the already-written file rather than re-fetching. Returns null (and
  /// callers should fall back to streaming the network URL directly) if the
  /// download fails.
  static Future<String?> ensureCached(String videoUrl) {
    if (videoUrl.isEmpty) return Future.value(null);
    return _inFlight.putIfAbsent(videoUrl, () => _download(videoUrl));
  }

  static Future<String?> _download(String videoUrl) async {
    try {
      final file = await _fileFor(videoUrl);
      if (await file.exists() && await file.length() > 0) return file.path;
      final res = await http
          .get(Uri.parse(videoUrl))
          .timeout(_downloadTimeout);
      if (res.statusCode != 200) return null;
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(videoUrl);
    }
  }

  static Future<File> _fileFor(String videoUrl) async {
    final dir = await getTemporaryDirectory();
    final ext = videoUrl.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    return File('${dir.path}/aura_video_cache_${_stableHash(videoUrl)}.$ext');
  }

  // dart:core's hashCode isn't guaranteed stable across runs, so cache keys
  // use a small FNV-1a hash of the URL instead.
  static String _stableHash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
