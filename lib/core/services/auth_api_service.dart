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

  Future<void> updateProfile({
    required String gender,
    String? displayName,
    String? username,
  }) async {
    final res = await _client.patch('/profile', {
      'gender': gender,
      if (displayName != null) 'displayName': displayName,
      if (username != null) 'username': username,
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

  Future<bool> isLoggedIn() => _client.isLoggedIn();

  Future<String?> get currentUserId => _client.userId;
}
