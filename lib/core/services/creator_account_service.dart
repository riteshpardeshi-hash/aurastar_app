import 'api_client.dart';

/// The `/creator/followers`, `/creator/following`, `/creator/insights`,
/// `/creator/settings`, `/creator/profile` (delete) endpoints — the "Creator
/// Profile" Swagger tag. Distinct from `CreatorPageService` (page setup /
/// onboarding funnel) and `CreatorsService` (plural public discovery).
class CreatorAccountService {
  final _client = ApiClient();

  /// Entries only carry `followerId`/`followingId`/`followingType` — no
  /// enriched name/avatar (`PaginatedFollowList` schema has no profile
  /// fields). Callers must enrich separately if they want display names.
  Future<List<Map<String, dynamic>>> fetchFollowers({
    int page = 1,
    int limit = 20,
  }) =>
      _fetchFollowList('/creator/followers', page: page, limit: limit);

  Future<List<Map<String, dynamic>>> fetchFollowing({
    int page = 1,
    int limit = 20,
  }) =>
      _fetchFollowList('/creator/following', page: page, limit: limit);

  /// Reads `pagination.total` off a 1-item page — `PaginatedFollowList`
  /// doesn't expose a dedicated count endpoint.
  Future<int> fetchFollowingCount() async {
    try {
      final res = await _client.get('/creator/following?page=1&limit=1', auth: true);
      if (res['status'] != 'success') return 0;
      final data = res['data'] as Map<String, dynamic>?;
      final pagination = data?['pagination'] as Map<String, dynamic>?;
      return (pagination?['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFollowList(
    String path, {
    required int page,
    required int limit,
  }) async {
    try {
      final res = await _client.get('$path?page=$page&limit=$limit', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'] as Map<String, dynamic>?;
      return (data?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchInsights() async {
    final res = await _client.get('/creator/insights', auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Date ranges / metrics / challengeIds available for the insights
  /// dashboard filters. Response schema is undocumented in Swagger (generic
  /// envelope) — return the raw map, caller reads defensively.
  Future<Map<String, dynamic>> fetchInsightsFilterOptions() async {
    try {
      final res = await _client.get('/creator/insights/filter-options', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// High-level performance summary (views/participants/aura/follower growth/
  /// challenge count) for the selected time window. Response schema is
  /// undocumented — return the raw map, caller reads defensively.
  Future<Map<String, dynamic>> fetchPerformanceOverview({String? dateRange}) async {
    try {
      final q = dateRange != null ? '?dateRange=$dateRange' : '';
      final res = await _client.get('/creator/insights/performance$q', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Time-series points for one metric. `metric` must be one of: views,
  /// participants, likes, shares, followers, auraEarned, rewardEarned,
  /// attempts. Per-point shape is undocumented — caller reads defensively.
  Future<List<Map<String, dynamic>>> fetchInsightsChart({
    required String metric,
    String? dateRange,
    DateTime? startDate,
    DateTime? endDate,
    String? challengeId,
  }) async {
    try {
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final q = [
        'metric=$metric',
        if (dateRange != null) 'dateRange=$dateRange',
        if (startDate != null) 'startDate=${fmt(startDate)}',
        if (endDate != null) 'endDate=${fmt(endDate)}',
        if (challengeId != null) 'challengeId=$challengeId',
      ].join('&');
      final res = await _client.get('/creator/insights/chart?$q', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'] as Map<String, dynamic>?;
      final points = data?['points'] ?? data?['series'] ?? data?['data'];
      if (points is! List) return [];
      return points.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Paginated, sortable list of the creator's challenges ranked by a
  /// performance metric. Pagination wrapper is documented (`PaginatedList`);
  /// per-item fields are not.
  Future<Map<String, dynamic>> fetchTopChallenges({
    String? sort,
    String? dateRange,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      String fmt(DateTime d) => d.toIso8601String().split('T').first;
      final q = [
        'page=$page',
        'limit=$limit',
        if (sort != null) 'sort=$sort',
        if (dateRange != null) 'dateRange=$dateRange',
        if (startDate != null) 'startDate=${fmt(startDate)}',
        if (endDate != null) 'endDate=${fmt(endDate)}',
      ].join('&');
      final res = await _client.get('/creator/insights/top-challenges?$q', auth: true);
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

  /// Created with defaults on first access — never null for an active creator.
  Future<Map<String, dynamic>> fetchSettings() async {
    final res = await _client.get('/creator/settings', auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Only supplied top-level fields are overwritten; nested objects
  /// (`notifications`, `linkedAccounts`) should be passed whole since the
  /// backend does not deep-merge them.
  Future<Map<String, dynamic>> updateSettings({
    String? visibility,
    Map<String, bool>? notifications,
    Map<String, String>? linkedAccounts,
  }) async {
    final res = await _client.put('/creator/settings', {
      if (visibility != null) 'visibility': visibility,
      if (notifications != null) 'notifications': notifications,
      if (linkedAccounts != null) 'linkedAccounts': linkedAccounts,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update settings';
    }
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Soft-deletes the creator profile and archives all live challenges; the
  /// account reverts to player mode. The underlying user account is kept.
  Future<void> deleteProfile() async {
    final res = await _client.delete('/creator/profile', auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to delete creator profile';
    }
  }
}
