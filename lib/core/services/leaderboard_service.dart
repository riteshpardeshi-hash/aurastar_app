import 'api_client.dart';

class LeaderboardService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchGlobal({
    int page = 1,
    int limit = 20,
  }) => _fetch('/leaderboard', page: page, limit: limit, auth: true);

  /// The global board with search, period and sort, plus the viewer's own
  /// standing (backend ADR 154). Throws on a network/server error so the
  /// screen can keep what it shows.
  Future<GlobalBoardPage> fetchGlobalBoard({
    int page = 1,
    int limit = 20,
    String search = '',
    String period = 'all',
    String sort = 'aura_desc',
  }) async {
    final q =
        Uri(
          queryParameters: {
            'page': '$page',
            'limit': '$limit',
            if (search.trim().isNotEmpty) 'search': search.trim(),
            'period': period,
            'sort': sort,
          },
        ).query;
    final res = await _client.get('/leaderboard?$q', auth: true);
    if (res['status'] != 'success')
      throw Exception(res['message'] ?? 'Leaderboard failed');
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final list =
        (data['responses'] as List? ??
                data['leaderboard'] as List? ??
                data['items'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
    final me =
        data['me'] is Map ? Map<String, dynamic>.from(data['me'] as Map) : null;
    return GlobalBoardPage(
      entries: list.map(normaliseLeaderboardEntry).toList(),
      total: (data['totalCount'] as num?)?.toInt() ?? list.length,
      me: me,
    );
  }

  /// The Challenge tab's cards: each joinable challenge with its participants,
  /// leader and the viewer's rank (backend ADR 154).
  Future<List<Map<String, dynamic>>> fetchChallengeBoards({
    int page = 1,
    int limit = 20,
    String search = '',
    String filter = 'all',
    String sort = 'participants_desc',
  }) async {
    final q =
        Uri(
          queryParameters: {
            'page': '$page',
            'limit': '$limit',
            if (search.trim().isNotEmpty) 'search': search.trim(),
            'filter': filter,
            'sort': sort,
          },
        ).query;
    final res = await _client.get('/leaderboard/challenges?$q', auth: true);
    if (res['status'] != 'success')
      throw Exception(res['message'] ?? 'Challenge boards failed');
    final data = res['data'] as Map<String, dynamic>? ?? {};
    return (data['responses'] as List? ?? []).cast<Map<String, dynamic>>();
  }

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
      final res = await _client.get(
        '$path?page=$page&limit=$limit',
        auth: auth,
      );
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list =
          data is Map
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
  final name =
      (user['displayName'] as String?)?.trim().isNotEmpty == true
          ? user['displayName'] as String
          : (user['name'] as String?)?.trim().isNotEmpty == true
          ? user['name'] as String
          : (user['profileName'] as String? ?? 'User');
  return {
    'id': (user['_id'] ?? user['id'] ?? e['userId'] ?? '') as String? ?? '',
    'name': name,
    'username':
        user['username'] as String? ?? user['profileName'] as String? ?? '',
    // `score` is the board's Aura (all-time, or earned this week/month); older
    // responses only had auraPoints.
    'score':
        ((e['score'] ??
                    e['auraPoints'] ??
                    e['totalRewards'] ??
                    e['aiScore'] ??
                    user['auraPoints'] ??
                    user['totalRewards'])
                as num?)
            ?.toInt() ??
        0,
    'stars': ((e['starsCount'] ?? e['stars']) as num?)?.toInt() ?? 0,
    'rank': (e['rank'] as num?)?.toInt(),
    'avatar': user['avatar'] as String? ?? '',
  };
}

class GlobalBoardPage {
  final List<Map<String, dynamic>> entries;
  final int total;

  /// The viewer's standing: rank (null when not on this board), score,
  /// gapToFirst, gapToNext. Null when signed out.
  final Map<String, dynamic>? me;

  const GlobalBoardPage({required this.entries, required this.total, this.me});
}
