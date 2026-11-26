import 'api_client.dart';

/// One of your ranks on a board (Global / country / city / a challenge).
class RankEntry {
  final String id;
  final String name;
  final int? rank;
  final int? total;
  final int? score;

  const RankEntry({
    required this.id,
    required this.name,
    this.rank,
    this.total,
    this.score,
  });
}

class ChallengeRank {
  final String challengeId;
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final int? rank;
  final int? total;
  final int? bestScore;

  const ChallengeRank({
    required this.challengeId,
    required this.title,
    this.thumbnailUrl = '',
    this.videoUrl = '',
    this.rank,
    this.total,
    this.bestScore,
  });
}

/// Everything the profile's Ranks tab shows (GET /leaderboard/me/ranks).
class MyRanks {
  final RankEntry? global;
  final RankEntry? country;
  final RankEntry? city;
  final List<ChallengeRank> challenges;

  const MyRanks({
    this.global,
    this.country,
    this.city,
    this.challenges = const [],
  });

  bool get isEmpty =>
      global?.rank == null &&
      country?.rank == null &&
      city?.rank == null &&
      challenges.isEmpty;
}

int? _int(dynamic v) => (v as num?)?.toInt();

RankEntry? _region(dynamic raw, String fallbackName) {
  if (raw is! Map) return null;
  return RankEntry(
    id: raw['_id'] as String? ?? '',
    name:
        (raw['name'] as String?)?.trim().isNotEmpty == true
            ? raw['name'] as String
            : fallbackName,
    rank: _int(raw['rank']),
    total: _int(raw['total']),
    score: _int(raw['score']),
  );
}

MyRanks parseMyRanks(Map<String, dynamic> data) {
  final challenges =
      (data['challenges'] as List? ?? [])
          .whereType<Map>()
          .map(
            (c) => ChallengeRank(
              challengeId: c['challengeId'] as String? ?? '',
              title: c['title'] as String? ?? '',
              thumbnailUrl: c['thumbnailUrl'] as String? ?? '',
              videoUrl: c['videoUrl'] as String? ?? '',
              rank: _int(c['rank']),
              total: _int(c['total']),
              bestScore: _int(c['bestScore']),
            ),
          )
          .where((c) => c.challengeId.isNotEmpty)
          .toList();
  return MyRanks(
    global: _region(data['global'], 'Global'),
    country: _region(data['country'], 'Your country'),
    city: _region(data['city'], 'Your city'),
    challenges: challenges,
  );
}

class RanksService {
  final _client = ApiClient();

  /// Your ranks everywhere, or null when the server can't say (offline, or an
  /// older backend without the endpoint) — the profile then shows its empty state.
  Future<MyRanks?> fetchMyRanks() async {
    try {
      final res = await _client.get('/leaderboard/me/ranks', auth: true);
      if (res['status'] != 'success') return null;
      final data = res['data'];
      if (data is! Map<String, dynamic>) return null;
      return parseMyRanks(data);
    } catch (_) {
      return null;
    }
  }
}
