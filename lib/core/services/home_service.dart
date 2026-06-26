import 'api_client.dart';
import '../config/api_config.dart';

class HomeService {
  final _client = ApiClient();

  Future<Map<String, dynamic>?> fetchFeatured() async {
    try {
      final res = await _client.get('/home/featured', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return data['challenge'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
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
}

// Normalises a ChallengeSummary (from home endpoints) into the UI shape.
// Tries videoUrl first, falls back to constructing from videoKey + mediaBaseUrl.
Map<String, dynamic> normaliseHomeSummary(Map<String, dynamic> c) {
  final rawUrl = c['videoUrl'] as String?;
  final key = c['videoKey'] as String? ?? '';
  final videoUrl = (rawUrl?.isNotEmpty == true)
      ? rawUrl!
      : (key.isNotEmpty && ApiConfig.mediaBaseUrl.isNotEmpty
          ? '${ApiConfig.mediaBaseUrl}/$key'
          : '');
  return {
    'id': c['_id'] as String? ?? '',
    'title': c['title'] as String? ?? '',
    'instructions': c['description'] as String? ?? c['title'] as String? ?? '',
    'videoUrl': videoUrl,
    'starsCount': (c['starsCount'] as num?)?.toInt() ?? 0,
    'submissionsCount': (c['submissionsCount'] as num?)?.toInt() ?? 0,
    'sourceType': c['sourceType'] as String? ?? '',
    'category': c['category'] as String? ?? '',
  };
}
