import 'api_client.dart';

class ChallengesService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchChallenges({
    String? category,
    String? difficulty,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
      if (category != null) 'category': category,
      if (difficulty != null) 'difficulty': difficulty,
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
      final names = list
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
          '/challenges/$challengeId/submissions?limit=$limit');
      final data = res['data'] as Map<String, dynamic>;
      return (data['submissions'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> presignSubmission(String challengeId) async {
    final res = await _client.post(
        '/challenges/$challengeId/submissions/presign', {}, auth: true);
    return res['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createSubmission(
      String challengeId, String videoKey) async {
    final res = await _client.post(
      '/challenges/$challengeId/submissions',
      {'videoKey': videoKey},
      auth: true,
    );
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
    required String videoKey,
  }) async {
    final res = await _client.post('/challenges', {
      'title': title,
      'description': description,
      if (instructions != null && instructions.isNotEmpty)
        'instructions': instructions,
      'category': categoryId,
      'difficulty': difficulty,
      'videoKey': videoKey,
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

  Future<Map<String, dynamic>?> fetchMySubmission(String challengeId) async {
    try {
      final res = await _client.get(
          '/challenges/$challengeId/submissions/me',
          auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['submission'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }
}

// Helper — normalises a backend challenge map into the fields the UI expects.
Map<String, dynamic> normaliseChallenge(Map<String, dynamic> c) {
  return {
    'id': c['_id'] as String? ?? '',
    'title': c['title'] as String? ?? '',
    'description': c['description'] as String? ?? '',
    'instructions': (c['instructions'] as String?)?.isNotEmpty == true
        ? c['instructions']
        : c['description'] as String? ?? '',
    'videoUrl': c['videoUrl'] as String? ?? '',
    'category': c['category'] as String? ?? '',
    'difficulty': c['difficulty'] as String? ?? '',
    'sourceType': c['sourceType'] as String? ?? '',
    'creatorId': c['creatorId'] as String? ?? '',
    'starsCount': (c['starsCount'] as num?)?.toInt() ?? 0,
    'submissionsCount': (c['submissionsCount'] as num?)?.toInt() ?? 0,
    'isActive': c['isActive'] as bool? ?? true,
    'createdAt': c['createdAt'],
  };
}
