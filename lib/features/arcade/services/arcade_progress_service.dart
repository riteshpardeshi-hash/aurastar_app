import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kStorageKey = 'aura_arcade_daily_progress';

class ArcadeProgress {
  final String? lastPlayedDate;
  final int streak;
  final Map<String, int> bestScores;
  final List<String> completedToday;

  const ArcadeProgress({
    this.lastPlayedDate,
    this.streak = 0,
    this.bestScores = const {},
    this.completedToday = const [],
  });

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _yesterdayKey() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  ArcadeProgress normalized() {
    if (lastPlayedDate == _todayKey()) return this;
    return ArcadeProgress(
      lastPlayedDate: lastPlayedDate,
      streak: streak,
      bestScores: bestScores,
      completedToday: const [],
    );
  }

  ArcadeProgress withScore(String gameId, int score) {
    final today = _todayKey();
    final alreadyPlayedToday = lastPlayedDate == today;
    final playedYesterday = lastPlayedDate == _yesterdayKey();
    return ArcadeProgress(
      lastPlayedDate: today,
      streak: alreadyPlayedToday
          ? streak
          : playedYesterday
              ? streak + 1
              : 1,
      completedToday: completedToday.contains(gameId)
          ? completedToday
          : [...completedToday, gameId],
      bestScores: {
        ...bestScores,
        gameId: score > (bestScores[gameId] ?? 0) ? score : (bestScores[gameId] ?? 0),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'lastPlayedDate': lastPlayedDate,
        'streak': streak,
        'bestScores': bestScores,
        'completedToday': completedToday,
      };

  factory ArcadeProgress.fromJson(Map<String, dynamic> json) => ArcadeProgress(
        lastPlayedDate: json['lastPlayedDate'] as String?,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        bestScores: Map<String, int>.from(
          (json['bestScores'] as Map? ?? {}).map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ),
        ),
        completedToday:
            List<String>.from(json['completedToday'] as List? ?? []),
      );
}

class ArcadeProgressService {
  static Future<ArcadeProgress> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null) return const ArcadeProgress();
      return ArcadeProgress.fromJson(
              jsonDecode(raw) as Map<String, dynamic>)
          .normalized();
    } catch (_) {
      return const ArcadeProgress();
    }
  }

  static Future<void> save(ArcadeProgress progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, jsonEncode(progress.toJson()));
    } catch (_) {}
  }
}
