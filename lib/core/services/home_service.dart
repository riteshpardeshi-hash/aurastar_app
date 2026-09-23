import 'api_client.dart';
import '../config/api_config.dart';

class HomeService {
  final _client = ApiClient();

  /// The admin-curated Featured carousel (ADR 092). Empty list when nothing is
  /// featured — the carousel then hides itself.
  Future<List<Map<String, dynamic>>> fetchFeatured() async {
    try {
      final res = await _client.get('/home/featured', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['challenges'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchBrandChallenges({int limit = 10}) async {
    try {
      final res = await _client.get('/home/brand-challenges?limit=$limit', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['docs'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchTrending({int limit = 10}) async {
    try {
      final res = await _client.get('/home/trending?limit=$limit', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['docs'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchTrendingCreators({int limit = 10}) async {
    try {
      final res = await _client.get('/home/trending-creators?limit=$limit', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['creators'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchBanners() async {
    try {
      final res = await _client.get('/home/banners', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['banners'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // Lives under the plain `/banners` tag (not `/home/*`) even though the
  // banner itself was fetched via fetchBanners() above — public, no auth,
  // not user-attributed, so failures are silently swallowed same as the
  // rest of this fire-and-forget-style service.
  Future<void> registerBannerClick(String id) async {
    try {
      await _client.post('/banners/$id/click', {});
    } catch (_) {}
  }
}

// Normalises a challenge from a `/home/*` endpoint into the flat UI shape.
//
// Read every field defensively: these endpoints return *populated* Challenge
// documents, so `category` / `creatorId` arrive as `{ _id, name, ... }` objects
// (not strings), and the video URL may be top-level (`presignS3Keys` flattens
// the populated `videoId` to `videoUrl` when it has a raw key) or still nested
// on `videoId` for an already-processed clip. A bare `as String` cast on any of
// these throws and red-screens the whole home feed.
String _hs(dynamic v) => v is String ? v : '';

Map<String, dynamic> normaliseHomeSummary(Map<String, dynamic> c) {
  final videoObj = c['videoId'];
  final videoMap = videoObj is Map ? videoObj : const <dynamic, dynamic>{};

  final rawUrl =
      _hs(c['videoUrl']).isNotEmpty ? _hs(c['videoUrl']) : _hs(videoMap['videoUrl']);
  final key = _hs(c['videoKey']).isNotEmpty ? _hs(c['videoKey']) : _hs(videoMap['videoKey']);
  final videoUrl = rawUrl.isNotEmpty
      ? rawUrl
      : (key.isNotEmpty && ApiConfig.mediaBaseUrl.isNotEmpty
          ? '${ApiConfig.mediaBaseUrl}/$key'
          : '');

  final category = c['category'];
  final categoryName = category is Map ? _hs(category['name']) : _hs(category);

  final thumb = _hs(c['thumbnailUrl']).isNotEmpty
      ? _hs(c['thumbnailUrl'])
      : _hs(videoMap['thumbnailUrl']);

  final description = _hs(c['description']);

  return {
    'id': _hs(c['_id']),
    'title': _hs(c['title']),
    'instructions': description.isNotEmpty ? description : _hs(c['title']),
    'videoUrl': videoUrl,
    'thumbnailUrl': thumb,
    'starsCount': (c['starsCount'] as num?)?.toInt() ?? 0,
    'submissionsCount': (c['submissionsCount'] as num?)?.toInt() ?? 0,
    'sourceType': _hs(c['sourceType']),
    'category': categoryName,
  };
}
