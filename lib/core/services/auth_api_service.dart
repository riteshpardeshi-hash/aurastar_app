import 'api_client.dart';

typedef AuthResult = ({
  String accessToken,
  String refreshToken,
  Map<String, dynamic> user,
  bool isNewUser,
});

class AuthApiService {
  final _client = ApiClient();

  /// Returns the OTP string when the backend sends it in the response (dev mode).
  /// Returns null in production when OTP is delivered via SMS.
  Future<String?> requestOtp({
    required String phone,
    required String countryCode,
  }) async {
    final res = await _client.post('/auth/otp/request', {
      'phone': phone,
      'countryCode': countryCode,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to send OTP';
    }
    final data = res['data'] as Map<String, dynamic>?;
    return data?['otp'] as String?;
  }

  Future<AuthResult> verifyOtp({
    required String phone,
    required String countryCode,
    required String otp,
  }) async {
    final res = await _client.post('/auth/otp/verify', {
      'phone': phone,
      'countryCode': countryCode,
      'otp': otp,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Incorrect OTP. Please try again.';
    }
    final data = res['data'] as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    await _client.saveSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: user['id'] as String,
    );
    return (
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      user: user,
      isNewUser: data['isNewUser'] as bool,
    );
  }

  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final res = await _client.get('/profile', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['user'] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<AuthResult> signInWithGoogle(String idToken) async {
    final res = await _client.post('/auth/google', {'idToken': idToken});
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Google sign-in failed';
    }
    return _saveAndReturn(res['data'] as Map<String, dynamic>);
  }

  Future<AuthResult> signInWithApple({
    required String idToken,
    required String authorizationCode,
  }) async {
    final res = await _client.post('/auth/apple', {
      'idToken': idToken,
      'authorizationCode': authorizationCode,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Apple sign-in failed';
    }
    return _saveAndReturn(res['data'] as Map<String, dynamic>);
  }

  Future<AuthResult> _saveAndReturn(Map<String, dynamic> data) async {
    final user = data['user'] as Map<String, dynamic>;
    final userId = (user['id'] ?? user['_id']) as String;
    await _client.saveSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: userId,
    );
    return (
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      user: user,
      isNewUser: data['isNewUser'] as bool? ?? false,
    );
  }

  Future<void> logout() async {
    final rt = await _client.refreshToken;
    if (rt != null) {
      try {
        await _client.post('/auth/logout', {'refreshToken': rt}, auth: true);
      } catch (_) {}
    }
    await _client.clearSession();
  }

  /// Revokes every refresh token for this user (all devices), then clears
  /// the local session. Access tokens on other devices stay valid until they
  /// naturally expire (max 15 minutes).
  Future<void> logoutAll() async {
    try {
      await _client.post('/auth/logout-all', {}, auth: true);
    } catch (_) {}
    await _client.clearSession();
  }

  Future<void> updateProfile({
    required String gender,
    String? displayName,
    String? username,
  }) async {
    final res = await _client.patch('/profile', {
      'gender': gender,
      if (displayName != null) 'displayName': displayName,
      // Backend field is `profileName`, not `username` (per Joi schema shared
      // by backend team) — Dart-side param name kept as `username` since that's
      // the UI concept everywhere else in the client.
      if (username != null) 'profileName': username,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update profile';
    }
  }

  Future<Map<String, dynamic>> getAvatarUploadUrl(String contentType) async {
    final res = await _client.get(
        '/profile/avatar/upload-url?contentType=$contentType',
        auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to get upload URL';
    }
    return res['data'] as Map<String, dynamic>;
  }

  Future<void> updateAvatar(String avatarUrl) async {
    final res = await _client.patch('/profile/avatar', {'avatarUrl': avatarUrl});
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update avatar';
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyVideos({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final res = await _client.get(
          '/profile/videos?page=$page&limit=$limit',
          auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['videos'] as List? ?? []).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchSavedChallenges({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final res = await _client.get(
          '/profile/saved-challenges?page=$page&limit=$limit',
          auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['challenges'] as List? ??
                data['savedChallenges'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchAchievements() async {
    try {
      final res = await _client.get('/profile/achievements', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['achievements'] as List? ??
                data['cards'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchAuraHistory({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final res = await _client.get(
          '/profile/aura/history?page=$page&limit=$limit',
          auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['transactions'] as List? ??
                data['history'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> fetchReferralStats() async {
    try {
      final res = await _client.get('/profile/referral', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['referral'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchRewards({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final q = [
        'page=$page',
        'limit=$limit',
        if (status != null) 'status=$status',
      ].join('&');
      final res = await _client.get('/profile/rewards?$q', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['rewards'] as List? ??
                data['docs'] as List? ??
                data['items'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> claimReward(String id) async {
    final res = await _client.post('/profile/rewards/$id/claim', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to claim reward';
    }
    final data = res['data'] as Map<String, dynamic>;
    return data['reward'] as Map<String, dynamic>?;
  }

  Future<int> fetchAuraBalance() async {
    try {
      final res = await _client.get('/aura/balance', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['auraPoints'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<Map<String, dynamic>?> fetchStreak() async {
    try {
      final res = await _client.get('/profile/streak', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['streak'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchReferralsList({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _client.get(
          '/profile/referrals/list?page=$page&limit=$limit',
          auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['referrals'] as List? ??
                data['docs'] as List? ??
                data['items'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> isLoggedIn() => _client.isLoggedIn();

  Future<String?> get currentUserId => _client.userId;
}
