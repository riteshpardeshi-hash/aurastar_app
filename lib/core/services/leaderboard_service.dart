import 'api_client.dart';

class LeaderboardService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchGlobal({
    int page = 1,
    int limit = 20,
  }) =>
      _fetch('/leaderboard', page: page, limit: limit, auth: true);

  Future<List<Map<String, dynamic>>> fetchFriends({
    int page = 1,
    int limit = 20,
  }) =>
      _fetch('/leaderboard/friends', page: page, limit: limit, auth: true);

  // No fetchChallenge() here — GET /leaderboard/challenge/{id} is empirically
  // broken (confirmed against the live backend: it returns an empty
  // `responses` array for challenges that have real, scored public
  // submissions via GET /challenges/{id}/submissions). Per-challenge boards
  // use ChallengesService().fetchSubmissions() + normaliseSubmissionEntry
  // instead — see leaderboard_screen.dart's _ChallengeBoard.

  Future<List<Map<String, dynamic>>> _fetch(
    String path, {
    required int page,
    required int limit,
    bool auth = false,
  }) async {
    try {
      final res =
          await _client.get('$path?page=$page&limit=$limit', auth: auth);
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list = data is Map
          ? (data['responses'] as List? ??
              data['leaderboard'] as List? ??
              data['items'] as List? ??
              data['docs'] as List? ??
              data['users'] as List? ??
              [])
          : (data is List ? data : []);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}

// Backend leaderboard entries are thinly documented in Swagger (generic
// `object` schemas) and may nest the ranked user under a `user` key or list
// fields flat on the entry itself — handle both shapes defensively, same
// pattern as `normaliseChallenge` in challenges_service.dart.
Map<String, dynamic> normaliseLeaderboardEntry(Map<String, dynamic> e) {
  final user = e['user'] is Map ? e['user'] as Map<String, dynamic> : e;
  final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
      ? user['displayName'] as String
      : (user['name'] as String?)?.trim().isNotEmpty == true
          ? user['name'] as String
          : (user['profileName'] as String? ?? 'User');
  return {
    'id': (user['_id'] ?? user['id'] ?? e['userId'] ?? '') as String? ?? '',
    'name': name,
    'username':
        user['username'] as String? ?? user['profileName'] as String? ?? '',
    'score': ((e['auraPoints'] ??
                e['totalRewards'] ??
                e['aiScore'] ??
                e['score'] ??
                user['auraPoints'] ??
                user['totalRewards']) as num?)
            ?.toInt() ??
        0,
    'stars': ((e['starsCount'] ?? e['stars']) as num?)?.toInt() ?? 0,
  };
}
