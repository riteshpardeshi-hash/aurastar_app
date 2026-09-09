import 'api_client.dart';

class BrandsService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchBrands({
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = [
        'page=$page',
        'limit=$limit',
        if (search != null && search.isNotEmpty)
          'search=${Uri.encodeComponent(search)}',
      ].join('&');
      final res = await _client.get('/brands?$q', auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchBrand(String id) async {
    try {
      final res = await _client.get('/brands/$id', auth: true);
      if (res['status'] != 'success') return null;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        final brand = data['brand'];
        if (brand is Map<String, dynamic>) {
          // The API nests the profile under `data.brand` but places the
          // viewer-scoped `isFollowing` flag as a *sibling* of it, not
          // inside it. Lift it in so normaliseBrand (and the profile
          // screen's Follow button) can see the real follow state instead
          // of always defaulting to false.
          return {
            ...brand,
            if (data.containsKey('isFollowing')) 'isFollowing': data['isFollowing'],
          };
        }
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchBrandChallenges(
    String id, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
          '/brands/$id/challenges?page=$page&limit=$limit',
          auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  /// Backend only exposes follower *ids* (paginated list), not a count, so we
  /// read the pagination total from a 1-item page instead of a dedicated
  /// count endpoint — same trick as `CreatorsService.fetchCreatorFollowerCount`.
  Future<int> fetchBrandFollowerCount(String id) async {
    try {
      final res =
          await _client.get('/brands/$id/followers?limit=1', auth: true);
      if (res['status'] != 'success') return 0;
      final data = res['data'];
      if (data is Map) {
        final pagination = data['pagination'] as Map<String, dynamic>?;
        return (pagination?['total'] as num?)?.toInt() ??
            (data['totalCount'] as num?)?.toInt() ??
            0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> followBrand(String id) => _setFollow(id, follow: true);

  Future<bool> unfollowBrand(String id) => _setFollow(id, follow: false);

  // See CreatorsService._setFollow — same fix, same reason: a swallowed
  // failure here left FollowButton with no way to tell the user a follow
  // didn't actually go through.
  Future<bool> _setFollow(String id, {required bool follow}) async {
    final res = follow
        ? await _client.post('/brands/$id/follow', {}, auth: true)
        : await _client.delete('/brands/$id/follow', auth: true);
    if (res['status'] != 'success') {
      throw Exception(res['message'] as String? ??
          'Failed to ${follow ? 'follow' : 'unfollow'} brand');
    }
    return true;
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is Map) {
      final list = data['responses'] as List? ??
          data['brands'] as List? ??
          data['challenges'] as List? ??
          data['items'] as List? ??
          data['docs'] as List? ??
          [];
      return list.cast<Map<String, dynamic>>();
    }
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }
}

// GET /brands and /brands/{id} have no per-item schema in Swagger (generic
// SuccessEnvelope/PaginatedResponse). The `/search?type=all` endpoint's
// `data.brands` entries are the one place field names are confirmed
// (`_id`/`displayName`/`username`/`avatar`); `BrandProfileUpdate` (the
// self-edit schema) additionally documents `brandName`/`companyName`/`logo`/
// `website`/`industry` — fall back across both naming schemes.
Map<String, dynamic> normaliseBrand(Map<String, dynamic> b) {
  final displayName = (b['displayName'] as String?)?.trim().isNotEmpty == true
      ? b['displayName'] as String
      : (b['brandName'] as String?)?.trim().isNotEmpty == true
          ? b['brandName'] as String
          : (b['companyName'] as String? ?? 'Brand');
  return {
    'id': b['_id'] as String? ?? b['id'] as String? ?? '',
    'displayName': displayName,
    'username': b['username'] as String? ?? '',
    'bio': b['bio'] as String? ?? b['industry'] as String? ?? '',
    'avatar': b['avatar'] as String? ?? b['logo'] as String? ?? '',
    'website': b['website'] as String? ?? '',
    'isFollowing': b['isFollowing'] as bool? ?? false,
    'isVerified': b['isVerified'] as bool? ?? false,
  };
}
