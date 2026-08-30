import 'api_client.dart';
import 'push_notification_service.dart';

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

  // Like [getProfile], but lets failures propagate instead of swallowing
  // them to `null`. Most callers just want "no profile, move on" and
  // already tolerate a null return, so this is additive rather than a
  // change to getProfile()'s contract. Callers that need to show the user
  // *why* the load failed (e.g. Dashboard's error screen, which used to
  // always claim "no internet" even for unrelated backend errors) should
  // use this and inspect the thrown error via humanizeError().
  Future<Map<String, dynamic>> getProfileOrThrow() async {
    final res = await _client.get('/profile', auth: true);
    if (res['status'] == 'success') {
      final data = res['data'] as Map<String, dynamic>;
      return data['user'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] as String? ?? 'Failed to load profile');
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
    // Must run before clearSession() — deregistering needs the still-valid
    // access token, and the DeviceToken row would otherwise keep receiving
    // pushes for an account this device is no longer signed into.
    await PushNotificationService().deregisterCurrentDevice();
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
    await PushNotificationService().deregisterCurrentDevice();
    try {
      await _client.post('/auth/logout-all', {}, auth: true);
    } catch (_) {}
    await _client.clearSession();
  }

  Future<void> updateProfile({
    required String gender,
    String? displayName,
    String? username,
    DateTime? dateOfBirth,
  }) async {
    final res = await _client.patch('/profile', {
      'gender': gender,
      if (displayName != null) 'displayName': displayName,
      // Backend field is `profileName`, not `username` (per Joi schema shared
      // by backend team) — Dart-side param name kept as `username` since that's
      // the UI concept everywhere else in the client.
      if (username != null) 'profileName': username,
      // Backend expects ISO 8601 `YYYY-MM-DD`.
      if (dateOfBirth != null)
        'dateOfBirth':
            '${dateOfBirth.year.toString().padLeft(4, '0')}-'
            '${dateOfBirth.month.toString().padLeft(2, '0')}-'
            '${dateOfBirth.day.toString().padLeft(2, '0')}',
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
        // Same paginated-list envelope as /profile/aura/history — the array
        // is wrapped under `responses`, not `videos` (verified live via
        // GET /profile/videos on 2026-07-31).
        return (data['responses'] as List? ??
                data['videos'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
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
        // Live response wraps the list as `responses` (verified via
        // GET /profile/aura/history on 2026-07-31); `transactions`/`history`
        // kept as fallbacks in case the backend's field name changes again.
        return (data['responses'] as List? ??
                data['transactions'] as List? ??
                data['history'] as List? ??
                [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> fetchReferralStats() async {
    try {
      final res = await _client.get('/referrals', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['referral'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  // GET /referrals/stats has no per-item schema in Swagger beyond "total
  // referrals made, aura earned from referrals, and recent activity" — field
  // names are guessed defensively, same pattern as elsewhere in this file.
  // Distinct from fetchReferralStats() (GET /referrals), which only returns
  // the code + a bare count.
  Future<Map<String, dynamic>?> fetchReferralStatsDetail() async {
    try {
      final res = await _client.get('/referrals/stats', auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return (data['stats'] as Map<String, dynamic>?) ?? data;
      }
    } catch (_) {}
    return null;
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

  Future<bool> applyReferralCode(String code) async {
    try {
      final res = await _client.post(
        '/referrals/apply',
        {'referralCode': code},
        auth: true,
      );
      return res['status'] == 'success';
    } catch (_) {}
    return false;
  }

  // GET /profile/rewards — fully documented `UserReward` schema, no field
  // guessing needed. Distinct from the aura/tier progression system in
  // core/models/aura_tier.dart: these are individually-awarded rewards
  // (streak completion, leaderboard win, brand challenge, admin grant,
  // participant target), not level-based.
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
      if (res['status'] != 'success') return [];
      final data = res['data'];
      final list = data is Map
          ? (data['responses'] as List? ?? data['rewards'] as List? ?? [])
          : (data is List ? data : []);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Only meaningful for `rewardType: 'coupon_code'` rewards — marks it
  /// claimed and returns the updated reward (with `couponCode` revealed).
  Future<Map<String, dynamic>?> claimReward(String id) async {
    try {
      final res = await _client.post('/profile/rewards/$id/claim', {}, auth: true);
      if (res['status'] == 'success') {
        final data = res['data'] as Map<String, dynamic>;
        return data['reward'] as Map<String, dynamic>?;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isLoggedIn() => _client.isLoggedIn();

  Future<String?> get currentUserId => _client.userId;
}
