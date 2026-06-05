import 'package:shared_preferences/shared_preferences.dart';

/// Tracks recently viewed video URLs so the app can hint at what to warm.
class VideoCacheService {
  VideoCacheService._();

  static const _recentKey = 'recently_viewed_videos';
  static const _maxEntries = 20;

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
}
