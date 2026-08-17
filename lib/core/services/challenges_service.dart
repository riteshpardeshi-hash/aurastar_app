import 'api_client.dart';

class ChallengesService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchChallenges({
    String? category,
    String? difficulty,
    String? sourceType,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (category != null) 'category': category,
      if (difficulty != null) 'difficulty': difficulty,
      if (sourceType != null) 'sourceType': sourceType,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final res = await _client.get('/challenges?$query');
    final data = res['data'] as Map<String, dynamic>;
    return (data['challenges'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> fetchChallenge(String id) async {
    try {
      final res = await _client.get('/challenges/$id');
      final data = res['data'] as Map<String, dynamic>;
      return data['challenge'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> fetchCategories() async {
    try {
      final res = await _client.get('/categories');
      final data = res['data'] as Map<String, dynamic>;
      final list = (data['categories'] as List).cast<Map<String, dynamic>>();
      final names =
          list
              .map((c) => (c['name'] ?? c['_id'] ?? '') as String)
              .where((n) => n.isNotEmpty)
              .toList();
      if (names.isNotEmpty) return names;
    } catch (_) {}
    return const ['Dance', 'Fitness', 'Fashion', 'Sports', 'Comedy', 'Skill'];
  }

  Future<List<Map<String, dynamic>>> fetchSubmissions(
    String challengeId, {
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
        '/challenges/$challengeId/submissions?limit=$limit',
      );
      final data = res['data'] as Map<String, dynamic>;
      return (data['submissions'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> presignSubmission(String challengeId) async {
    final res = await _client.post(
      '/challenges/$challengeId/submissions/presign',
      {},
      auth: true,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to get upload URL';
    }
    return res['data'] as Map<String, dynamic>;
  }

  // POST /challenges/{id}/submissions runs the full scoring pipeline
  // synchronously server-side — content-safety moderation, face
  // verification, and rubric-driven AI scoring are each their own Gemini
  // call before the response comes back (see openapi.yaml). That routinely
  // runs past ApiClient's default 15s CRUD timeout even when nothing is
  // wrong, which was surfacing a real "video doesn't match the challenge"
  // verdict as a misleading "network error, retrying" screen instead.
  // 90s matches AuraSubmittedPopup's own client-side polling timeout — the
  // point at which the app already considers scoring unusually slow.
  static const _scoringTimeout = Duration(seconds: 90);

  Future<Map<String, dynamic>> createSubmission(
    String challengeId,
    String videoId,
  ) async {
    final res = await _client.post(
      '/challenges/$challengeId/submissions',
      {'videoId': videoId},
      auth: true,
      timeout: _scoringTimeout,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to create submission';
    }
    return res['data']['submission'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> presignChallenge() async {
    final res = await _client.post('/challenges/presign', {}, auth: true);
    return res['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createChallenge({
    required String title,
    required String description,
    String? instructions,
    required String categoryId,
    required String difficulty,
    required String videoId,
  }) async {
    final res = await _client.post('/challenges', {
      'title': title,
      'description': description,
      if (instructions != null && instructions.isNotEmpty)
        'instructions': instructions,
      'category': categoryId,
      'difficulty': difficulty,
      'videoId': videoId,
    }, auth: true);
    return res['data']['challenge'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchCategoriesWithIds() async {
    try {
      final res = await _client.get('/categories');
      final data = res['data'] as Map<String, dynamic>;
      return (data['categories'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // id → name, so a challenge's `category` (an ObjectId) can be resolved to
  // the display name categoryIconAsset is keyed by. Categories rarely change
  // within a session, and every thumbnail grid across the app needs this
  // same lookup, so the fetch is shared/cached here rather than repeated
  // per-screen.
  static Future<Map<String, String>>? _categoryNameMapFuture;
  Future<Map<String, String>> fetchCategoryNameMap() {
    return _categoryNameMapFuture ??= fetchCategoriesWithIds().then(
      (cats) => {
        for (final c in cats)
          if ((c['_id'] as String?)?.isNotEmpty == true)
            c['_id'] as String: c['name'] as String? ?? '',
      },
    );
  }

  Future<Map<String, dynamic>?> fetchMySubmission(String challengeId) async {
    try {
      final res = await _client.get(
        '/challenges/$challengeId/submissions/me',
        auth: true,
      );
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['submission'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }
}

// `creatorId`/`category` come back as a plain ID string for most challenges,
// but as a populated object (e.g. {_id, role, displayName, avatar}) for some —
// extract a stable string either way instead of crashing the cast.
String _extractRefId(dynamic v) {
  if (v is String) return v;
  if (v is Map) return v['_id'] as String? ?? v['name'] as String? ?? '';
  return '';
}

// Maps a Submission's backend `status`/`verdict` to the four-value
// vocabulary ('approved'/'rejected'/'ai_error'/'pending') the result UI
// (AuraSubmittedPopup, PostScoreActionScreen, MyAccountScreen/AllVideosScreen
// video grids) is built around. Per openapi.yaml's Submission schema,
// `status` is `pending | scored | failed | flagged` and `verdict` (only set
// once scored) is `EXCELLENT | GOOD | AVERAGE | WEAK | INVALID` — the API
// never sends the literal strings 'PASS'/'FAIL' that earlier client code
// checked for, so that comparison always fell through to the failure
// branch even for a fully approved, points-awarding submission.
String submissionStatusFromApi(Map<String, dynamic> s) {
  switch (s['status'] as String?) {
    case 'scored':
      return s['verdict'] == 'INVALID' ? 'rejected' : 'approved';
    case 'flagged':
      return 'rejected';
    case 'failed':
      return 'ai_error';
    default:
      return 'pending';
  }
}

// GET /challenges/{id}/submissions (the backend's own docs call this "the
// public leaderboard" — already sorted by aiScore descending) never joins a
// display name: `userId` comes back as a bare id string or a populated
// `{_id}` object, never with a name. There's no public endpoint to resolve a
// player id to a name (creators/brands lookups 404 for regular players;
// player profiles are otherwise private) — name/username are left blank
// here so callers can apply an honest, rank-based fallback instead of
// fabricating an identity.
Map<String, dynamic> normaliseSubmissionEntry(Map<String, dynamic> s) {
  return {
    'id': _extractRefId(s['userId']),
    'name': '',
    'username': '',
    'score': (s['aiScore'] as num?)?.toInt() ?? 0,
    'stars': (s['starsCount'] as num?)?.toInt() ?? 0,
  };
}

// Helper — normalises a backend challenge map into the fields the UI expects.
Map<String, dynamic> normaliseChallenge(Map<String, dynamic> c) {
  return {
    'id': c['_id'] as String? ?? '',
    'title': c['title'] as String? ?? '',
    'description': c['description'] as String? ?? '',
    'instructions':
        (c['instructions'] as String?)?.isNotEmpty == true
            ? c['instructions']
            : c['description'] as String? ?? '',
    'videoUrl': c['videoUrl'] as String? ?? '',
    'thumbnailUrl': c['thumbnailUrl'] as String? ?? '',
    'category': _extractRefId(c['category']),
    'difficulty': c['difficulty'] as String? ?? '',
    'sourceType': c['sourceType'] as String? ?? '',
    'creatorId': _extractRefId(c['creatorId']),
    'starsCount': (c['starsCount'] as num?)?.toInt() ?? 0,
    'submissionsCount': (c['submissionsCount'] as num?)?.toInt() ?? 0,
    'isActive': c['isActive'] as bool? ?? true,
    'status': c['status'] as String? ?? 'approved',
    'createdAt': c['createdAt'],
  };
}
