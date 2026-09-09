import 'api_client.dart';

/// The "Creator Dashboard" tag — `/creator/dashboard/*` — a newer, additive
/// set of endpoints purpose-built for the mobile home dashboard screen.
/// Distinct from `CreatorPageService.fetchDashboard()` (`GET /creator/dashboard`,
/// singular, legacy/undocumented) which Swagger explicitly says this does
/// NOT replace. Unlike most Creator tags, every response here has a real
/// named schema — no `pickField` guessing needed.
class CreatorDashboardService {
  final _client = ApiClient();

  /// Combined payload for the dashboard screen in one call: summary/growth
  /// totals, dynamic `cards`, the `gateProgress` widget (auto-picks the
  /// LIVE/APPROVED challenge closest to its next gate unless [challengeId]
  /// overrides it), `pendingActions` + count, and `unreadNotificationsCount`.
  Future<Map<String, dynamic>> fetchOverview({String? challengeId}) async {
    try {
      final q = challengeId != null ? '?challengeId=$challengeId' : '';
      final res =
          await _client.get('/creator/dashboard/overview$q', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Challenge status counts, participant stats (today/week/month/lifetime),
  /// and engagement stats, over [dateRange] (today/7d/30d/90d/year/custom).
  Future<Map<String, dynamic>> fetchStatistics({
    String dateRange = '30d',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final q = [
        'dateRange=$dateRange',
        if (dateRange == 'custom' && startDate != null)
          'startDate=${startDate.toUtc().toIso8601String()}',
        if (dateRange == 'custom' && endDate != null)
          'endDate=${endDate.toUtc().toIso8601String()}',
      ].join('&');
      final res =
          await _client.get('/creator/dashboard/statistics?$q', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> fetchGateProgress({String? challengeId}) async {
    try {
      final q = challengeId != null ? '?challengeId=$challengeId' : '';
      final res =
          await _client.get('/creator/dashboard/gate-progress$q', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Outstanding action items — pending review, changes requested,
  /// rejections, unread gate unlocks, unverified/incomplete profile.
  Future<Map<String, dynamic>> fetchPendingActions() async {
    try {
      final res =
          await _client.get('/creator/dashboard/pending-actions', auth: true);
      if (res['status'] != 'success') {
        return {'count': 0, 'actions': <Map<String, dynamic>>[]};
      }
      final data = res['data'] as Map<String, dynamic>? ?? {};
      return {
        'count': (data['count'] as num?)?.toInt() ?? 0,
        'actions': (data['actions'] as List?)?.cast<Map<String, dynamic>>() ??
            [],
      };
    } catch (_) {
      return {'count': 0, 'actions': <Map<String, dynamic>>[]};
    }
  }

  /// Creator-relevant subset of notifications (challenge status updates +
  /// admin announcements), each with a computed `category`.
  Future<Map<String, dynamic>> fetchNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
        '/creator/dashboard/notifications?page=$page&limit=$limit',
        auth: true,
      );
      if (res['status'] != 'success') {
        return {
          'items': <Map<String, dynamic>>[],
          'totalCount': 0,
          'totalPages': 1,
        };
      }
      final data = res['data'] as Map<String, dynamic>? ?? {};
      return {
        'items':
            (data['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        'totalCount': (data['totalCount'] as num?)?.toInt() ?? 0,
        'totalPages': (data['totalPages'] as num?)?.toInt() ?? 1,
      };
    } catch (_) {
      return {
        'items': <Map<String, dynamic>>[],
        'totalCount': 0,
        'totalPages': 1,
      };
    }
  }

  /// Ordered, dynamically-computed card list (key/title/value/order) — the
  /// backend can add new cards without a client change, so render generically
  /// off `title`/`value` rather than switching on `key`.
  Future<List<Map<String, dynamic>>> fetchCards() async {
    try {
      final res = await _client.get('/creator/dashboard/cards', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final cards =
          (data['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      cards.sort((a, b) =>
          ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0));
      return cards;
    } catch (_) {
      return [];
    }
  }
}
