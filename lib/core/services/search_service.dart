import 'api_client.dart';

class SearchService {
  final _client = ApiClient();

  /// Search across challenges, brands, creators, categories.
  /// [type]: 'all' | 'challenges' | 'brands' | 'creators' | 'categories'
  /// [page]/[limit] are only honoured by the backend when [type] is a
  /// specific type — `type=all` always returns a fixed 10-item preview per
  /// collection with no pagination.
  /// Returns the `data` map from the response.
  Future<Map<String, dynamic>> search(
    String q, {
    String type = 'all',
    int page = 1,
    int limit = 20,
  }) async {
    final encoded = Uri.encodeComponent(q);
    final res = await _client.get(
      '/search?q=$encoded&type=$type&page=$page&limit=$limit',
      auth: true,
    );
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  Future<List<Map<String, dynamic>>> fetchRecent() async {
    try {
      final res = await _client.get('/search/recent', auth: true);
      final data = res['data'] as Map<String, dynamic>;
      return (data['items'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(String entityType, String entityId) async {
    try {
      await _client.post(
        '/search/history',
        {'entityType': entityType, 'entityId': entityId},
        auth: true,
      );
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      await _client.delete('/search/recent', auth: true);
    } catch (_) {}
  }
}
