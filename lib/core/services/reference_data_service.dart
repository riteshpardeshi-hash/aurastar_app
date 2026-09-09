import 'package:flutter/foundation.dart';
import 'api_client.dart';
import '../data/countries_data.dart';
import '../data/cities_data.dart';

class ReferenceDataService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchCountries() async {
    try {
      final res = await _client.get('/countries');
      final data = res['data'] as Map<String, dynamic>;
      final list = (data['countries'] as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) return list.map(_normaliseRef).toList();
    } catch (e) {
      debugPrint('[Ref] fetchCountries error: $e');
    }
    return kFallbackCountries;
  }

  // `countryId` is the backend's real id, used for the API call. `countryCode`
  // is the ISO alpha-2 code (e.g. 'IN') that kFallbackCities is keyed by —
  // the backend's `_id` never matches those keys, so it must be passed
  // separately when falling back.
  Future<List<Map<String, dynamic>>> fetchCities(
    String countryId, {
    String? countryCode,
  }) async {
    try {
      final res = await _client.get('/countries/$countryId/cities');
      final data = res['data'] as Map<String, dynamic>;
      final list = (data['cities'] as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) return list.map(_normaliseRef).toList();
    } catch (e) {
      debugPrint('[Ref] fetchCities error: $e');
    }
    return kFallbackCities[countryCode ?? countryId] ?? [];
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
    final res = await _client.patch('/profile/country', {'countryId': countryId});
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
    final res = await _client.patch('/profile/interests', {'interestIds': interestIds});
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
