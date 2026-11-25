import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/ai_ads_service.dart';

/// Which images and videos a creator has already seen in a campaign, kept on the phone. The
/// media icon on Create AI Videos counts only the ones not seen yet; opening My AI videos marks
/// everything it shows as seen (it used to show the total, so it never cleared). Each one is
/// remembered with its state, so a video seen while generating counts as new again once it's
/// ready.
class AiSeenWork {
  /// What "seen" is remembered as: the item plus whether it was generating or finished.
  static String keyOf(AiGeneration g) => '${g.id}:${g.isDone ? 'done' : 'running'}';

  static String _key(String campaignId) => 'ai_ads.seen_work.$campaignId';

  static Future<Set<String>> load(String campaignId) async {
    try {
      // Never hold the screen up for this: if the store is slow, show every item as new.
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      return (prefs.getStringList(_key(campaignId)) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markSeen(String campaignId, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_key(campaignId)) ?? const <String>[]).toSet()..addAll(ids);
      await prefs.setStringList(_key(campaignId), seen.toList());
    } catch (_) {
      // Not being able to remember only means the badge shows these again.
    }
  }
}
