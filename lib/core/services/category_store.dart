import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Thrown when the categories can't be loaded and nothing is saved on the
/// device yet. The message is safe to show to the user.
class CategoryLoadException implements Exception {
  const CategoryLoadException([this.message = 'We couldn\'t load the categories.']);
  final String message;
  @override
  String toString() => message;
}

/// The one source of challenge categories for the whole app.
///
/// Categories change rarely (an admin adds or retires one), yet five screens
/// used to fetch them separately, so every screen paid a network round trip
/// and a single dropped connection left a creator with no categories at all.
/// Now:
///
/// * the list is saved on the device ([SharedPreferences]) and returned
///   straight away, even offline;
/// * a saved list older than [maxAge] is still returned, and refreshed in the
///   background for next time;
/// * concurrent callers share one request;
/// * only `{_id, name}` is kept — the API's presigned thumbnail URLs expire,
///   so they must never be stored.
///
/// Call [invalidate] when the backend says a category no longer exists.
class CategoryStore {
  CategoryStore._();

  static final CategoryStore instance = CategoryStore._();

  static const _prefsKey = 'category_store_v1';
  static const maxAge = Duration(hours: 6);
  static const _pageSize = 100;
  static const _maxPages = 10;

  List<Map<String, dynamic>>? _categories;
  DateTime? _fetchedAt;
  Future<List<Map<String, dynamic>>>? _inFlight;

  /// What is already in memory, for a first frame without a spinner.
  List<Map<String, dynamic>>? peek() => _categories == null ? null : List.unmodifiable(_categories!);

  /// The categories, from memory or the device when available (refreshing
  /// them in the background once stale), otherwise from the network.
  /// [forceRefresh] skips the saved copy. Throws [CategoryLoadException] only
  /// when there is nothing saved and the network fails.
  Future<List<Map<String, dynamic>>> load({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_categories == null) await _readSaved();
      final saved = _categories;
      if (saved != null) {
        if (_isStale) unawaited(_refresh().catchError((Object _) => saved));
        return List.unmodifiable(saved);
      }
    }
    return List.unmodifiable(await _refresh());
  }

  /// The id → name map thumbnails use to show a challenge's category.
  Future<Map<String, String>> nameById() async {
    final list = await load();
    return {for (final c in list) c['_id'] as String: c['name'] as String};
  }

  /// Forget the saved list (e.g. a category was retired); the next [load]
  /// fetches fresh.
  Future<void> invalidate() async {
    _categories = null;
    _fetchedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Clears memory only — for tests.
  @visibleForTesting
  void resetForTest() {
    _categories = null;
    _fetchedAt = null;
    _inFlight = null;
  }

  bool get _isStale => _fetchedAt == null || DateTime.now().difference(_fetchedAt!) > maxAge;

  Future<List<Map<String, dynamic>>> _refresh() => _inFlight ??= _fetchWithRetry().whenComplete(() => _inFlight = null);

  Future<List<Map<String, dynamic>>> _fetchWithRetry() async {
    for (var attempt = 1; ; attempt++) {
      try {
        final list = await _fetchAllPages();
        _categories = list;
        _fetchedAt = DateTime.now();
        await _save(list);
        return list;
      } catch (e) {
        debugPrint('[Categories] load failed (attempt $attempt): $e');
        if (attempt >= 2) throw const CategoryLoadException();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllPages() async {
    final result = <Map<String, dynamic>>[];
    String? cursor;
    for (var page = 0; page < _maxPages; page++) {
      final query = 'limit=$_pageSize${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}';
      final res = await ApiClient().get('/categories?$query');
      if (res['status'] != 'success') {
        throw Exception(res['message'] as String? ?? 'Failed to load categories');
      }
      final data = res['data'] as Map<String, dynamic>;
      for (final raw in (data['categories'] as List? ?? const [])) {
        final c = raw as Map<String, dynamic>;
        final id = c['_id'] as String?;
        final name = (c['name'] as String?)?.trim();
        if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
          result.add({'_id': id, 'name': name});
        }
      }
      final pagination = data['pagination'] as Map<String, dynamic>?;
      cursor = pagination?['nextCursor'] as String?;
      if (pagination?['hasNextPage'] != true || cursor == null) break;
    }
    return result;
  }

  Future<void> _readSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = (decoded['categories'] as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;
      _categories = list;
      _fetchedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
    } catch (_) {
      // A corrupt or old-format entry is simply ignored.
    }
  }

  Future<void> _save(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'categories': list}),
      );
    } catch (_) {}
  }
}
