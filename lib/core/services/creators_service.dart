import 'api_client.dart';

class CreatorsService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchCreators({
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
      final res = await _client.get('/creators?$q', auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchCreator(String id) async {
    try {
      final res = await _client.get('/creators/$id', auth: true);
      if (res['status'] != 'success') return null;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        final creator = data['creator'];
        if (creator is Map<String, dynamic>) {
          // The API nests the profile under `data.creator` but places the
          // viewer-scoped `isFollowing` flag as a *sibling* of it, not
          // inside it. Lift it in so normaliseCreator (and the profile
          // screen's Follow button) can see the real follow state instead
          // of always defaulting to false.
          return {
            ...creator,
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

  Future<List<Map<String, dynamic>>> fetchCreatorVideos(
    String id, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
          '/creators/$id/videos?page=$page&limit=$limit',
          auth: true);
      if (res['status'] != 'success') return [];
      return _extractList(res['data']);
    } catch (_) {
      return [];
    }
  }

  /// Backend only exposes follower *ids* (`PaginatedFollowList`), not counts,
  /// so we read the pagination total from a 1-item page instead of a
  /// dedicated count endpoint.
  Future<int> fetchCreatorFollowerCount(String id) async {
    try {
      final res =
          await _client.get('/creators/$id/followers?limit=1', auth: true);
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

  Future<bool> followCreator(String id) => _setFollow(id, follow: true);

  Future<bool> unfollowCreator(String id) => _setFollow(id, follow: false);

  // Used to silently swallow every failure (network error, 409 "already
  // following", auth issue) into `false` with no message, so FollowButton
  // had nothing to show the user and a failed follow looked identical to a
  // successful one from the UI. Throwing here (matching the rest of this
  // file's create/delete calls, e.g. CreatorPageService.createPage) lets
  // FollowButton surface the real reason instead.
  Future<bool> _setFollow(String id, {required bool follow}) async {
    final res = follow
        ? await _client.post('/creators/$id/follow', {}, auth: true)
        : await _client.delete('/creators/$id/follow', auth: true);
    if (res['status'] != 'success') {
      throw Exception(res['message'] as String? ??
          'Failed to ${follow ? 'follow' : 'unfollow'} creator');
    }
    return true;
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is Map) {
      final list = data['responses'] as List? ??
          data['data'] as List? ??
          data['creators'] as List? ??
          data['videos'] as List? ??
          data['items'] as List? ??
          data['docs'] as List? ??
          [];
      return list.cast<Map<String, dynamic>>();
    }
    if (data is List) return data.cast<Map<String, dynamic>>();
    return [];
  }
}

// Backed by the documented `CreatorSummary`/`CreatorProfile` schemas, which
// use different field names for the same concepts (avatar vs profileImage) —
// normalise both shapes to one set of keys the UI can rely on.
Map<String, dynamic> normaliseCreator(Map<String, dynamic> c) {
  return {
    'id': c['_id'] as String? ?? c['userId'] as String? ?? c['id'] as String? ?? '',
    'displayName': (c['displayName'] as String?)?.trim().isNotEmpty == true
        ? c['displayName'] as String
        : (c['name'] as String? ?? c['username'] as String? ?? 'Creator'),
    'username': c['username'] as String? ?? '',
    'bio': c['bio'] as String? ?? '',
    'avatar': c['avatar'] as String? ?? c['profileImage'] as String? ?? '',
    'auraPoints': (c['auraPoints'] as num?)?.toInt() ?? 0,
    'tier': c['tier'] as String?,
    'isFollowing': c['isFollowing'] as bool? ?? false,
    'isVerified': c['isVerified'] as bool? ?? false,
  };
}

// `/creators/{id}/videos` returns `Submission` records (a creator's public
// video posts are their public challenge submissions), not a separate Video
// model — normalise the fields the video grid needs.
Map<String, dynamic> normaliseCreatorVideo(Map<String, dynamic> v) {
  return {
    'id': v['_id'] as String? ?? '',
    'challengeId': v['challengeId'] as String? ?? '',
    'videoUrl': v['videoUrl'] as String? ?? '',
    // GET /creators/{id}/videos has no documented per-item schema, so this
    // is a defensive read (same "try the field, fall back gracefully"
    // pattern as everywhere else this file guesses across key names) — if
    // the backend doesn't actually send it, this is just always null and
    // VideoThumbnailWidget falls back to its existing frame-extraction path
    // exactly as before.
    'thumbnailUrl': v['thumbnailUrl'] as String?,
    'aiScore': (v['aiScore'] as num?)?.toInt(),
    'createdAt': v['createdAt'],
  };
}
