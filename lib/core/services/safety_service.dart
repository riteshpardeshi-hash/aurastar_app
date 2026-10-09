import 'dart:async';

import 'api_client.dart';

/// Report and block (backend ADR 117).
///
/// A block is two-way: once someone is blocked, neither side sees the other's profile,
/// videos, challenges or comments. Blocking a brand also hides its challenges, ads and AI
/// ad campaigns. A report goes to the admin Moderation Queue.
class SafetyService {
  final _client = ApiClient();

  static final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after a successful block or unblock. Screens that stay mounted (the shell's
  /// tabs, open search results, the reels feed) reload on it, so a blocked account's
  /// content leaves them at once — and comes back on unblock (Apple guideline 1.2).
  static Stream<void> get changes => _changes.stream;

  /// Reasons the backend accepts, with the label shown to the user.
  static const reasons = <String, String>{
    'spam': 'Spam',
    'harassment': 'Harassment or bullying',
    'impersonation': 'Pretending to be someone else',
    'inappropriate': 'Inappropriate content',
    'scam': 'Scam or fraud',
    'other': 'Something else',
  };

  Future<void> block(String userId) async {
    final res = await _client.post('/users/$userId/block', {}, auth: true);
    _ok(res, "Couldn't block this account");
    _changes.add(null);
  }

  Future<void> unblock(String userId) async {
    final res = await _client.delete('/users/$userId/block', auth: true);
    _ok(res, "Couldn't unblock this account");
    _changes.add(null);
  }

  /// Accounts the signed-in user blocked, newest first.
  Future<List<BlockedAccount>> blocked({int page = 1, int limit = 50}) async {
    final res = await _client.get('/users/blocked?page=$page&limit=$limit', auth: true);
    _ok(res, "Couldn't load blocked accounts");
    final data = res['data'];
    final rows = data is Map ? (data['responses'] ?? data['docs'] ?? []) : (data is List ? data : []);
    return [
      for (final r in rows as List)
        if (r is Map) BlockedAccount.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// Reports a profile (player, creator or brand). True when it was already reported by you.
  Future<bool> reportUser(String userId, String reason, {String? details}) =>
      _report('/users/$userId/report', reason, details);

  /// Reports a video. True when it was already reported by you.
  Future<bool> reportVideo(String videoId, String reason, {String? details}) =>
      _report('/videos/$videoId/report', reason, details);

  Future<bool> _report(String path, String reason, String? details) async {
    final res = await _client.post(path, {
      'reason': reason,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    }, auth: true);
    _ok(res, "Couldn't send the report");
    final data = res['data'];
    return data is Map && data['alreadyReported'] == true;
  }

  void _ok(Map<String, dynamic> res, String fallback) {
    if (res['status'] != 'success') throw SafetyException(res['message'] as String? ?? fallback);
  }
}

class SafetyException implements Exception {
  final String message;
  SafetyException(this.message);
  @override
  String toString() => message;
}

class BlockedAccount {
  final String id;
  final String displayName;
  final String? profileName;
  final String? role;
  final String? avatar;

  const BlockedAccount({required this.id, required this.displayName, this.profileName, this.role, this.avatar});

  factory BlockedAccount.fromJson(Map<String, dynamic> j) => BlockedAccount(
    id: '${j['_id'] ?? ''}',
    displayName: '${j['displayName'] ?? 'Account'}',
    profileName: j['profileName'] as String?,
    role: j['role'] as String?,
    avatar: j['avatar'] as String?,
  );
}
