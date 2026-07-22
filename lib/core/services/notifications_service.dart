import 'api_client.dart';
import 'creator_challenges_service.dart' show pickField, pickInt, pickString;

class NotificationsService {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> fetchNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
        '/notifications?page=$page&limit=$limit',
        auth: true,
      );
      if (res['status'] != 'success') {
        return {
          'items': <Map<String, dynamic>>[],
          'totalCount': 0,
          'page': page,
          'totalPages': 1,
        };
      }
      final data = res['data'] as Map<String, dynamic>?;
      final items =
          (data?['responses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return {
        'items': items.map(normaliseNotification).toList(),
        'totalCount': (data?['totalCount'] as num?)?.toInt() ?? items.length,
        'page': (data?['page'] as num?)?.toInt() ?? page,
        'totalPages': (data?['totalPages'] as num?)?.toInt() ?? 1,
      };
    } catch (_) {
      return {
        'items': <Map<String, dynamic>>[],
        'totalCount': 0,
        'page': page,
        'totalPages': 1,
      };
    }
  }

  Future<int> fetchUnreadCount() async {
    try {
      final res = await _client.get('/notifications/unread-count', auth: true);
      if (res['status'] != 'success') return 0;
      final data = res['data'] as Map<String, dynamic>? ?? {};
      return pickInt(data, ['unreadCount', 'count']);
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAllRead() async {
    final res = await _client.patch('/notifications/read-all', {});
    if (res['status'] != 'success') {
      throw Exception(res['message'] as String? ?? 'Failed to mark all as read');
    }
  }

  Future<void> markRead(String id) async {
    final res = await _client.patch('/notifications/$id/read', {});
    if (res['status'] != 'success') {
      throw Exception(res['message'] as String? ?? 'Failed to mark as read');
    }
  }

  Future<void> deleteNotification(String id) async {
    final res = await _client.delete('/notifications/$id', auth: true);
    if (res['status'] != 'success') {
      throw Exception(res['message'] as String? ?? 'Failed to delete notification');
    }
  }
}

// `GET /notifications` resolves to the generic SuccessEnvelope with no
// per-item schema in Swagger, so field names are best-guess via
// pickField/pickString (same defensive pattern as creator_challenges_service).
Map<String, dynamic> normaliseNotification(Map<String, dynamic> n) {
  return {
    'id': pickString(n, ['_id', 'id']),
    'message': pickString(n, ['message', 'body', 'text', 'title']),
    'type': pickString(n, ['type', 'category'], fallback: 'general'),
    'isRead': (pickField(n, ['isRead', 'read']) as bool?) ?? false,
    'createdAt': pickField(n, ['createdAt', 'created_at']),
  };
}
