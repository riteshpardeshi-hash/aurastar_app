import 'api_client.dart';

/// The reward tracks the backend exposes to players. There are two, and they
/// are separate systems on the backend:
///
///  1. **UserReward ledger** (`/profile/rewards`) — per-user rewards of type
///     `aura_points` or `coupon_code`, awarded for `streak_completion`,
///     `admin_manual`, `brand_challenge`, `challenge_participant_target`, or
///     `leaderboard_top`. A `coupon_code` reward hides its code until claimed
///     via `POST /profile/rewards/{id}/claim`.
///
///  2. **Offer vouchers / coupons** (`/profile/offer-vouchers`, backend ADRs
///     082–084) — coupons won either by finishing inside a challenge/campaign
///     offer's top-`rankLimit` band (`type=leaderboard`) or by crossing a
///     level boundary that has a `LEVEL` offer (`type=level`). Granted
///     automatically by the scoring pipeline (also surfaced as
///     `data.levelUpOffers` + `data.leaderboardOffers` on the submission
///     response) and redeemed by opening each entry's `redeemUrl`. Each entry
///     is either `sourcing: POOL` (a real single-use code) or
///     `sourcing: CATALOG` (a partner-network deal opened via our own
///     `/r/:grantId` redirect).
///
/// See docs/decisions/006-rewards-and-leaderboard-vouchers.md and
/// docs/decisions/016-catalog-vs-pool-coupon-sourcing.md.
class RewardsService {
  final ApiClient _client = ApiClient();

  // ── UserReward ledger ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRewards({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = [
        'page=$page',
        'limit=$limit',
        if (status != null) 'status=$status',
      ].join('&');
      final res = await _client.get('/profile/rewards?$q', auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  /// Marks a `coupon_code` reward claimed and returns the updated reward with
  /// its `couponCode` revealed. Meaningless for `aura_points` rewards.
  /// Returns null (no throw) on 4xx — e.g. 409 if already claimed.
  Future<Map<String, dynamic>?> claimReward(String id) async {
    try {
      final res =
          await _client.post('/profile/rewards/$id/claim', {}, auth: true);
      if (res['status'] == 'success') {
        return (res['data'] as Map<String, dynamic>?)?['reward']
            as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  // ── Leaderboard Offer vouchers ────────────────────────────────────────

  /// The user's offer wins, newest first. [type] filters to one kind:
  /// `'level'` (level-up offers) or `'leaderboard'` (rank-band offers);
  /// omit for both. Rows do not currently carry `sourcing`/`merchantName` —
  /// infer CATALOG from `redeemUrl` containing `/r/` (see [couponIsCatalog]).
  Future<List<Map<String, dynamic>>> fetchOfferVouchers({
    String? type,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = [
        'page=$page',
        'limit=$limit',
        if (type != null) 'type=$type',
      ].join('&');
      final res =
          await _client.get('/profile/offer-vouchers?$q', auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  /// Claims one still-`AVAILABLE` code from a challenge's own voucher pool —
  /// the "legacy claim pool" path, distinct from the rank-gated auto-grants.
  /// The challenge must be LIVE and a player may claim at most once per
  /// challenge. Returns the claimed voucher payload, or null (no throw) on
  /// 409 (already claimed / out of stock) or any error.
  ///
  /// Not wired to any UI yet: no player-facing field currently signals which
  /// challenges have a claimable pool. Kept here so the entry point is a
  /// one-liner once the backend surfaces that.
  Future<Map<String, dynamic>?> claimChallengeOffer(String challengeId) async {
    try {
      final res = await _client
          .post('/challenges/$challengeId/offers/claim', {}, auth: true);
      if (res['status'] == 'success') {
        final data = res['data'];
        return data is Map<String, dynamic> ? data : null;
      }
    } catch (_) {}
    return null;
  }

  // `/profile/rewards` uses the documented PaginatedList envelope
  // (`data.responses`). `/profile/offer-vouchers` is documented only as a
  // generic success envelope with an untyped `data` object, so fall back
  // across the key names the backend might use for the array.
  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map) {
      final list = data['responses'] ??
          data['rewards'] ??
          data['vouchers'] ??
          data['grants'] ??
          data['items'] ??
          const <dynamic>[];
      return (list as List).cast<Map<String, dynamic>>();
    }
    return const [];
  }
}
