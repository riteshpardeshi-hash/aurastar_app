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

  /// Returns the scored submission plus any coupons this submission won.
  ///
  /// Per the mobile coupon-integration contract (backend ADRs 082–084) the
  /// response carries coupons in **two** arrays that we concatenate into
  /// `coupons` — the app treats them uniformly and branches only on each
  /// entry's `sourcing` (`POOL` vs `CATALOG`):
  ///  - `data.levelUpOffers[]` — the user's Aura crossed a level boundary and
  ///    an admin has a `LEVEL` offer for that level.
  ///  - `data.leaderboardOffers[]` — the scored submission moved the user into
  ///    a brand offer's top-N rank band (was `data.grantedVouchers`, which the
  ///    backend renamed; still accepted here for transitional compatibility).
  ///
  /// Empty for the vast majority of submissions; a failure computing the
  /// grants server-side never fails the submission, so `[]` then too.
  ///
  /// `auraBalance` (running Aura total after this submission) and `levelUp`
  /// (non-null only when a level boundary was crossed) are surfaced for
  /// callers that want them; the dashboard already updates the wallet and
  /// fires the level-up animation off its own profile stream.
  Future<
      ({
        Map<String, dynamic> submission,
        List<Map<String, dynamic>> coupons,
        int? auraBalance,
        Map<String, dynamic>? levelUp,
      })> createSubmission(
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
    final data = res['data'] as Map<String, dynamic>;

    List<Map<String, dynamic>> arr(String key) =>
        (data[key] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return (
      submission: data['submission'] as Map<String, dynamic>,
      coupons: [
        ...arr('levelUpOffers'),
        // `grantedVouchers` is the pre-rename name for `leaderboardOffers`.
        ...(data['leaderboardOffers'] != null
            ? arr('leaderboardOffers')
            : arr('grantedVouchers')),
      ],
      auraBalance: (data['auraBalance'] as num?)?.toInt(),
      levelUp: data['levelUp'] as Map<String, dynamic>?,
    );
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
        // Per openapi.yaml this endpoint returns a `submissions` array
        // (newest first), not a single `submission` object — reading the
        // latter key here always came back null, which made the
        // participation-gated "See Leaderboard" button look permanently
        // locked even for challenges the user had already taken.
        final submissions =
            (data['submissions'] as List?)?.cast<Map<String, dynamic>>();
        if (submissions != null && submissions.isNotEmpty) {
          return submissions.first;
        }
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
    case null:
    case 'pending':
      return 'pending';
    default:
      // The documented status enum is pending|scored|failed|flagged. Any
      // other non-empty value is a server-side state the client can't
      // interpret — treat it as an AI error (which routes to manual admin
      // review and keeps the result UI's dismiss/exit path working) rather
      // than a silent 'pending', which used to leave AuraSubmittedPopup
      // polling forever and PostScoreActionScreen stuck on a blank result.
      return 'ai_error';
  }
}

// GET /challenges/{id}/submissions (the backend's own docs call this "the
// public leaderboard" — already sorted by aiScore descending). `userId` comes
// back populated: a `{_id, displayName?, avatar?}` object (the OpenAPI spec
// still types it as a bare string — it's stale). `displayName` is only
// present when that user set one, so callers still need a rank-based fallback
// for the rest; there's no public endpoint to resolve a player id to a name
// (creators/brands lookups 404 for regular players).
Map<String, dynamic> normaliseSubmissionEntry(Map<String, dynamic> s) {
  final u = s['userId'];
  String pick(String key) =>
      u is Map ? (u[key] as String?)?.trim() ?? '' : '';
  final name = pick('displayName').isNotEmpty
      ? pick('displayName')
      : pick('name').isNotEmpty
          ? pick('name')
          : pick('username');
  return {
    'id': _extractRefId(s['userId']),
    'name': name,
    'username': pick('username'),
    'score': (s['aiScore'] as num?)?.toInt() ?? 0,
    'stars': (s['starsCount'] as num?)?.toInt() ?? 0,
    'createdAt': s['createdAt'],
  };
}

/// Turns the raw submissions list (already score-desc) into leaderboard rows
/// with **one row per user** — a user who submitted several videos to the
/// same challenge appears once, at their best score. Without this the board
/// shows the same person on several consecutive rows (their every attempt),
/// which is not what a leaderboard means and also throws the rank numbers
/// off. Mirrors the backend's own Aura rule, where only a user's personal
/// best for a challenge counts (`netAurasAwarded = aiScore - previousBest`).
List<Map<String, dynamic>> leaderboardFromSubmissions(
  List<Map<String, dynamic>> raw,
) {
  final bestByUser = <String, Map<String, dynamic>>{};
  final noId = <Map<String, dynamic>>[];
  for (final s in raw) {
    final e = normaliseSubmissionEntry(s);
    final id = e['id'] as String;
    if (id.isEmpty) {
      noId.add(e); // can't dedupe a row with no user id — keep it as-is
      continue;
    }
    final existing = bestByUser[id];
    if (existing == null || (e['score'] as int) > (existing['score'] as int)) {
      bestByUser[id] = e;
    }
  }
  return [...bestByUser.values, ...noId]
    ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
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
