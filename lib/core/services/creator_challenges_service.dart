import 'api_client.dart';

/// The `/creator/challenges/*` + `/creator/challenge/*` "Creator Challenges"
/// draft → review → publish pipeline. A creator's challenge moves through
/// `submissionStatus`: DRAFT → PENDING_REVIEW → (APPROVED | REJECTED |
/// CHANGES_REQUESTED) → [publish] → LIVE. CHANGES_REQUESTED loops back to
/// DRAFT-like editing, then `resubmit` returns it to PENDING_REVIEW.
class CreatorChallengesService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final res = await _client.get('/creator/challenge/categories', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'];
      return data is List ? data.cast<Map<String, dynamic>>() : [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSubmissionRules() async {
    try {
      final res = await _client.get('/creator/challenge-submission-rules');
      if (res['status'] != 'success') return [];
      final data = res['data'] as Map<String, dynamic>?;
      return (data?['rules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyChallenges({
    String? submissionStatus,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = [
        'page=$page',
        'limit=$limit',
        if (submissionStatus != null) 'submissionStatus=$submissionStatus',
      ].join('&');
      final res =
          await _client.get('/creator/challenges/submissions?$q', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'] as Map<String, dynamic>?;
      return (data?['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// `key` must be passed back as `videoKey` to [createDraft]/[updateDraft].
  Future<Map<String, dynamic>> getReferenceVideoUploadUrl() async {
    final res =
        await _client.post('/creator/challenge/reference-video', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to get upload URL';
    }
    return res['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createDraft({
    required String title,
    required String category,
    required String difficulty,
    required String videoKey,
    String? description,
    String? thumbnailKey,
    Map<String, dynamic>? challengeInstructions,
  }) async {
    final res = await _client.post(
      '/creator/challenges',
      {
        'title': title,
        'category': category,
        'difficulty': difficulty,
        'videoKey': videoKey,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (thumbnailKey != null && thumbnailKey.isNotEmpty)
          'thumbnailKey': thumbnailKey,
        if (challengeInstructions != null)
          'challengeInstructions': challengeInstructions,
      },
      auth: true,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to create challenge draft';
    }
    return res['data']['challenge'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> fetchDraft(String id) async {
    try {
      final res = await _client.get('/creator/challenges/$id', auth: true);
      if (res['status'] != 'success') return null;
      return res['data']['challenge'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Only allowed while the draft is DRAFT or CHANGES_REQUESTED — 400s otherwise.
  Future<Map<String, dynamic>> updateDraft(
    String id, {
    String? title,
    String? category,
    String? difficulty,
    String? description,
    String? thumbnailKey,
    Map<String, dynamic>? challengeInstructions,
  }) async {
    final res = await _client.put('/creator/challenges/$id', {
      if (title != null) 'title': title,
      if (category != null) 'category': category,
      if (difficulty != null) 'difficulty': difficulty,
      if (description != null) 'description': description,
      if (thumbnailKey != null) 'thumbnailKey': thumbnailKey,
      if (challengeInstructions != null)
        'challengeInstructions': challengeInstructions,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update challenge draft';
    }
    return res['data']['challenge'] as Map<String, dynamic>;
  }

  /// Full preview with real presigned `videoUrl`/`thumbnailUrl`, shown before submit.
  Future<Map<String, dynamic>?> fetchPreview(String id) async {
    try {
      final res = await _client.get('/creator/challenges/$id/preview', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Lightweight polling endpoint for list cards.
  Future<Map<String, dynamic>?> fetchStatus(String id) async {
    try {
      final res = await _client.get('/creator/challenges/$id/status', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// DRAFT → PENDING_REVIEW. The creator must acknowledge the submission
  /// rules first (see [fetchSubmissionRules]).
  Future<Map<String, dynamic>> submit(String id) async {
    final res = await _client.post(
      '/creator/challenges/$id/submit',
      {'rulesAccepted': true},
      auth: true,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to submit for review';
    }
    return res['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> fetchReviewStatus(String id) async {
    try {
      final res =
          await _client.get('/creator/challenges/$id/review-status', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchFeedback(String id) async {
    try {
      final res = await _client.get('/creator/challenges/$id/feedback', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// CHANGES_REQUESTED → PENDING_REVIEW. Update the draft via [updateDraft]
  /// to address feedback before calling this.
  Future<Map<String, dynamic>> resubmit(String id) async {
    final res = await _client.post('/creator/challenges/$id/resubmit', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to resubmit';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// APPROVED → LIVE. Awards the creator `auraScore` Aura Points on success.
  Future<Map<String, dynamic>> publish(String id, {bool? notifyFollowers}) async {
    final res = await _client.post(
      '/creator/challenges/$id/publish',
      {if (notifyFollowers != null) 'notifyFollowers': notifyFollowers},
      auth: true,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to publish challenge';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Only available once a challenge is APPROVED or LIVE.
  Future<Map<String, dynamic>?> fetchLaunchConfig(String id) async {
    try {
      final res =
          await _client.get('/creator/challenges/$id/launch-config', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Only APPROVED challenges can have launch config updated — LIVE is immutable.
  Future<Map<String, dynamic>> updateLaunchConfig(
    String id, {
    String? coverImageKey,
    DateTime? launchAt,
    bool? notifyFollowers,
  }) async {
    final res = await _client.put('/creator/challenges/$id/launch-config', {
      if (coverImageKey != null) 'coverImageKey': coverImageKey,
      'launchAt': launchAt?.toUtc().toIso8601String(),
      if (notifyFollowers != null) 'notifyFollowers': notifyFollowers,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update launch config';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Statuses/categories/date-ranges the creator can filter their "My
  /// Challenges" list by. Response schema is undocumented in Swagger
  /// (generic envelope) — return the raw map, caller reads defensively.
  Future<Map<String, dynamic>> fetchChallengeFilters() async {
    try {
      final res = await _client.get('/creator/challenges/filters', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Soft-archive — hides from player feeds, preserves all data.
  Future<void> archive(String id) async {
    final res = await _client.patch('/creator/challenges/$id/archive', {});
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to archive challenge';
    }
  }

  /// Creates a new DRAFT copy (status/submissionStatus/dates reset).
  Future<Map<String, dynamic>> duplicate(String id) async {
    final res = await _client.post('/creator/challenges/$id/duplicate', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to duplicate challenge';
    }
    final data = res['data'] as Map<String, dynamic>?;
    return (data?['challenge'] as Map<String, dynamic>?) ?? data ?? {};
  }

  /// Engagement stats: participants, attempts, pass/fail, aura distributed,
  /// views. Response schema is undocumented (generic envelope) — return the
  /// raw map, caller reads defensively.
  Future<Map<String, dynamic>> fetchStats(String id) async {
    try {
      final res = await _client.get('/creator/challenges/$id/stats', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Paginated list of users who attempted this challenge.
  Future<Map<String, dynamic>> fetchParticipants(
    String id, {
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? sort,
    String? attemptRange,
    String? dateRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final q = [
        'page=$page',
        'limit=$limit',
        if (search != null && search.isNotEmpty) 'search=${Uri.encodeQueryComponent(search)}',
        if (status != null) 'status=$status',
        if (sort != null) 'sort=$sort',
        if (attemptRange != null) 'attemptRange=$attemptRange',
        if (dateRange != null) 'dateRange=$dateRange',
        if (startDate != null) 'startDate=${fmt(startDate)}',
        if (endDate != null) 'endDate=${fmt(endDate)}',
      ].join('&');
      final res = await _client.get('/creator/challenges/$id/participants?$q', auth: true);
      final data = res['data'] as Map<String, dynamic>?;
      return {
        'items': (data?['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'totalCount': (data?['totalCount'] as num?)?.toInt() ?? 0,
        'page': (data?['page'] as num?)?.toInt() ?? page,
        'totalPages': (data?['totalPages'] as num?)?.toInt() ?? 1,
      };
    } catch (_) {
      return {'items': <Map<String, dynamic>>[], 'totalCount': 0, 'page': page, 'totalPages': 1};
    }
  }

  /// Aggregate participant stats: total, pass/fail/pending split, attempt
  /// distribution. Response schema is undocumented — return the raw map.
  Future<Map<String, dynamic>> fetchParticipantsSummary(String id) async {
    try {
      final res =
          await _client.get('/creator/challenges/$id/participants/summary', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Verdicts/sort options/date/attempt ranges available for the participants
  /// list filter UI. Response schema is undocumented — the [fetchParticipants]
  /// query enums (status/sort/attemptRange/dateRange) are already known from
  /// Swagger, so this is a defensive supplement, not the source of truth.
  Future<Map<String, dynamic>> fetchParticipantsFilters(String id) async {
    try {
      final res =
          await _client.get('/creator/challenges/$id/participants/filters', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Detailed profile + attempt-history summary for one participant.
  Future<Map<String, dynamic>> fetchParticipantDetail(String id, String playerId) async {
    try {
      final res = await _client
          .get('/creator/challenges/$id/participants/$playerId', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Paginated attempts made by one participant on this challenge.
  Future<Map<String, dynamic>> fetchParticipantAttempts(
    String id,
    String playerId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
          '/creator/challenges/$id/participants/$playerId/attempts?page=$page&limit=$limit',
          auth: true);
      final data = res['data'] as Map<String, dynamic>?;
      return {
        'items': (data?['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'totalCount': (data?['totalCount'] as num?)?.toInt() ?? 0,
        'page': (data?['page'] as num?)?.toInt() ?? page,
        'totalPages': (data?['totalPages'] as num?)?.toInt() ?? 1,
      };
    } catch (_) {
      return {'items': <Map<String, dynamic>>[], 'totalCount': 0, 'page': page, 'totalPages': 1};
    }
  }
}

// `category` arrives as a populated Category object on a draft, but as a
// plain ObjectId string on create/update request echoes — handle both.
Map<String, dynamic> normaliseCreatorChallenge(Map<String, dynamic> c) {
  final categoryRaw = c['category'];
  final categoryId = categoryRaw is Map
      ? categoryRaw['_id'] as String? ?? ''
      : categoryRaw?.toString() ?? '';
  final categoryName =
      categoryRaw is Map ? categoryRaw['name'] as String? ?? '' : '';
  return {
    'id': c['_id'] as String? ?? '',
    'title': c['title'] as String? ?? '',
    'description': c['description'] as String? ?? '',
    'categoryId': categoryId,
    'categoryName': categoryName,
    'difficulty': c['difficulty'] as String? ?? '',
    'videoKey': c['videoKey'] as String? ?? '',
    'submissionStatus': c['submissionStatus'] as String? ?? 'DRAFT',
    'auraScore': (c['auraScore'] as num?)?.toInt(),
    'changeRequests': (c['changeRequests'] as List?)?.cast<String>() ?? [],
    'adminFeedback': c['adminFeedback'] as String?,
    'starsCount': (c['starsCount'] as num?)?.toInt() ?? 0,
    'submissionsCount': (c['submissionsCount'] as num?)?.toInt() ?? 0,
    'createdAt': c['createdAt'],
    'updatedAt': c['updatedAt'],
    'submittedAt': c['submittedAt'],
    'publishedAt': c['publishedAt'],
  };
}

/// Looks up the first present key from [candidates] in [map] — for reading
/// fields from Swagger-undocumented (generic-envelope) responses where the
/// exact backend key spelling is a best guess (e.g. `totalParticipants` vs
/// `participantCount`). Returns null if none of the candidates are present.
dynamic pickField(Map<String, dynamic> map, List<String> candidates) {
  for (final key in candidates) {
    if (map.containsKey(key) && map[key] != null) return map[key];
  }
  return null;
}

int pickInt(Map<String, dynamic> map, List<String> candidates, {int fallback = 0}) {
  final v = pickField(map, candidates);
  if (v is num) return v.toInt();
  return fallback;
}

String pickString(Map<String, dynamic> map, List<String> candidates, {String fallback = ''}) {
  final v = pickField(map, candidates);
  if (v is String) return v;
  return fallback;
}
