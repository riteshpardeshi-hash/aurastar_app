import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Thrown when countries/cities couldn't be loaded from the backend. The
/// message is safe to show to the user.
class ReferenceDataException implements Exception {
  final String message;
  const ReferenceDataException(this.message);

  @override
  String toString() => message;
}

final _backendIdPattern = RegExp(r'^[a-fA-F0-9]{24}$');

/// True for a real backend id (a 24-hex MongoDB ObjectId) — the only kind of
/// id PATCH /profile/country and /profile/city accept.
bool isBackendId(Object? id) => id is String && _backendIdPattern.hasMatch(id);

class ReferenceDataService {
  final _client = ApiClient();

  // Countries and cities are saved to the profile by id, so they must only
  // ever come from the backend. There used to be a hardcoded fallback list
  // here for when the request failed; its ids ('IN', 'IN_MUM', …) could never
  // be saved, so a single flaky request turned into "City ID must be a valid
  // 24-character ID" at Continue. Now a failure is retried once, then
  // surfaced so the screen can offer a retry.

  Future<List<Map<String, dynamic>>> fetchCountries() async {
    final list = await _fetchList('/countries', 'countries');
    if (list.isEmpty) {
      throw const ReferenceDataException(
        "Couldn't load countries. Tap to retry.",
      );
    }
    return list;
  }

  /// An empty list is a valid answer (no cities set up for that country).
  Future<List<Map<String, dynamic>>> fetchCities(String countryId) =>
      _fetchList('/countries/$countryId/cities?limit=100', 'cities');

  Future<List<Map<String, dynamic>>> _fetchList(String path, String key) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final res = await _client.get(path);
        final data = res['data'] as Map<String, dynamic>;
        final list = (data[key] as List).cast<Map<String, dynamic>>();
        return list
            .map(_normaliseRef)
            .where((item) => isBackendId(item['id']))
            .toList();
      } catch (e) {
        debugPrint('[Ref] GET $path failed (attempt $attempt): $e');
        if (attempt >= 2) {
          throw ReferenceDataException("Couldn't load $key. Tap to retry.");
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchInterests() async {
    try {
      final res = await _client.get('/interests');
      final data = res['data'] as Map<String, dynamic>;
      final list = (data['interests'] as List).cast<Map<String, dynamic>>();
      return list.map(_normaliseRef).toList();
    } catch (e) {
      debugPrint('[Ref] fetchInterests error: $e');
      return [];
    }
  }

  Future<void> saveCountry(String countryId) async {
    final res = await _client.patch('/profile/country', {
      'countryId': countryId,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to save country';
    }
  }

  Future<void> saveCity(String cityId) async {
    final res = await _client.patch('/profile/city', {'cityId': cityId});
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to save city';
    }
  }

  Future<void> saveInterests(List<String> interestIds) async {
    final res = await _client.patch('/profile/interests', {
      'interestIds': interestIds,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to save interests';
    }
  }
}

// Maps `_id` → `id` so the UI always uses `item['id']` consistently.
Map<String, dynamic> _normaliseRef(Map<String, dynamic> item) {
  if (item.containsKey('_id') && !item.containsKey('id')) {
    return {...item, 'id': item['_id'] as String? ?? ''};
  }
  return item;
}
