import 'api_client.dart';

class FriendsService {
  final _client = ApiClient();

  Future<List<Map<String, dynamic>>> fetchFriends({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
          '/friends?page=$page&limit=$limit', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list = data is Map
          ? (data['responses'] as List? ??
              data['friends'] as List? ??
              data['items'] as List? ??
              data['docs'] as List? ??
              [])
          : (data is List ? data : []);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // Item shape is undocumented in Swagger (generic SuccessEnvelope) — guess
  // across the key names used elsewhere in this codebase's list endpoints,
  // same defensive pattern as normaliseLeaderboardEntry.
  Future<List<Map<String, dynamic>>> fetchPendingRequests() async {
    try {
      final res = await _client.get('/friends/pending', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list = data is Map
          ? (data['requests'] as List? ??
              data['pending'] as List? ??
              data['items'] as List? ??
              data['docs'] as List? ??
              [])
          : (data is List ? data : []);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSuggestions() async {
    try {
      final res = await _client.get('/friends/suggestions', auth: true);
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list = data is Map
          ? (data['suggestions'] as List? ??
              data['users'] as List? ??
              data['items'] as List? ??
              data['docs'] as List? ??
              [])
          : (data is List ? data : []);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<bool> sendRequest(String receiverId) async {
    try {
      final res = await _client.post(
        '/friends/request',
        {'receiverId': receiverId},
        auth: true,
      );
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> respondToRequest(String requestId, {required bool accept}) async {
    try {
      final res = await _client.patch(
        '/friends/request/$requestId',
        {'action': accept ? 'accept' : 'reject'},
      );
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFriend(String friendId) async {
    try {
      final res = await _client.delete('/friends/$friendId', auth: true);
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }
}

// Backend friend/request/suggestion entries are thinly documented (generic
// `object` schemas) and may nest the other user under a 'user'/'sender'/
// 'requester' key or list fields flat on the entry itself — handle both
// shapes defensively, same pattern as normaliseLeaderboardEntry.
Map<String, dynamic> normaliseFriendUser(Map<String, dynamic> e) {
  final user = e['user'] is Map
      ? e['user'] as Map<String, dynamic>
      : e['sender'] is Map
          ? e['sender'] as Map<String, dynamic>
          : e['requester'] is Map
              ? e['requester'] as Map<String, dynamic>
              : e['friend'] is Map
                  ? e['friend'] as Map<String, dynamic>
                  : e;
  final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
      ? user['displayName'] as String
      : (user['name'] as String?)?.trim().isNotEmpty == true
          ? user['name'] as String
          : (user['profileName'] as String? ?? 'User');
  return {
    'id': (user['_id'] ??
            user['id'] ??
            e['userId'] ??
            e['senderId'] ??
            e['requesterId'] ??
            '') as String? ??
        '',
    'requestId': (e['_id'] ?? e['id'] ?? e['requestId'] ?? '') as String? ?? '',
    'name': name,
    'username':
        user['username'] as String? ?? user['profileName'] as String? ?? '',
    'avatarUrl': user['avatarUrl'] as String? ?? user['photoUrl'] as String?,
  };
}
