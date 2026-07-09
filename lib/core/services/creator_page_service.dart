import 'api_client.dart';

/// Covers the singular `/creator/*` "Creator Page" + "Creator Program"
/// endpoints — the onboarding funnel a regular user goes through to become a
/// creator (as opposed to `CreatorsService`, which is the plural `/creators/*`
/// public-discovery API for browsing already-active creators).
class CreatorPageService {
  final _client = ApiClient();

  /// `currentStep`: NOT_ELIGIBLE | ELIGIBLE | SETUP | ACTIVE.
  Future<Map<String, dynamic>> fetchSetupStatus() async {
    final res = await _client.get('/creator/setup-status', auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> fetchEligibility() async {
    final res = await _client.get('/creator/eligibility', auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  /// `progressPercentage` toward the 500-Aura threshold, plus
  /// `suggestedChallenges` (`ChallengeSummary[]`) to help close the gap.
  Future<Map<String, dynamic>> fetchProgress() async {
    final res = await _client.get('/creator/progress', auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> fetchRules() async {
    final res = await _client.get('/creator/rules');
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<List<String>> fetchCategories() async {
    try {
      final res = await _client.get('/creator/categories');
      final data = res['data'] as Map<String, dynamic>?;
      return (data?['categories'] as List?)?.cast<String>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Does not reserve the name — call [reserveUsername] to hold it.
  Future<Map<String, dynamic>> checkUsername(String username) async {
    final res = await _client
        .post('/creator/check-username', {'username': username}, auth: true);
    return (res['data'] as Map<String, dynamic>?) ?? {};
  }

  /// 15-minute hold; `POST /creator/page` must be called before it expires.
  Future<Map<String, dynamic>> reserveUsername(String username) async {
    final res = await _client.post(
        '/creator/reserve-username', {'username': username},
        auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to reserve username';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Requires an unexpired reservation for [username] from [reserveUsername].
  /// Creates an ACTIVE page immediately — there is no admin-approval step in
  /// this backend, unlike the old Firestore `creator_applications` flow.
  Future<Map<String, dynamic>> createPage({
    required String displayName,
    required String username,
    String? bio,
    String? profileImage,
    String? category,
    Map<String, String>? socialLinks,
  }) async {
    final res = await _client.post(
      '/creator/page',
      {
        'displayName': displayName,
        'username': username,
        if (bio != null && bio.isNotEmpty) 'bio': bio,
        if (profileImage != null && profileImage.isNotEmpty)
          'profileImage': profileImage,
        if (category != null && category.isNotEmpty) 'category': category,
        if (socialLinks != null && socialLinks.isNotEmpty)
          'socialLinks': socialLinks,
      },
      auth: true,
    );
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to create creator page';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Returns null if the caller has no creator page yet.
  Future<Map<String, dynamic>?> fetchOwnPage() async {
    try {
      final res = await _client.get('/creator/page', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Username cannot be changed here — only bio/profileImage/category/socialLinks.
  Future<Map<String, dynamic>> updatePage({
    String? bio,
    String? profileImage,
    String? category,
    Map<String, String>? socialLinks,
  }) async {
    final res = await _client.put('/creator/page', {
      if (bio != null) 'bio': bio,
      if (profileImage != null) 'profileImage': profileImage,
      if (category != null) 'category': category,
      if (socialLinks != null) 'socialLinks': socialLinks,
    });
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update creator page';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Returns `{uploadUrl, key}` — PUT the image binary to `uploadUrl`, then
  /// pass `key` back as `profileImage` to [createPage]/[updatePage]. Unlike
  /// the user-avatar upload flow, this does NOT return a public URL.
  Future<Map<String, dynamic>> getProfileImageUploadUrl() async {
    final res =
        await _client.post('/creator/upload-profile-image', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to get upload URL';
    }
    return res['data'] as Map<String, dynamic>;
  }

  /// Public — only ACTIVE pages are visible (DRAFT/SUSPENDED/BANNED → 404).
  Future<Map<String, dynamic>?> fetchPublicPage(String username) async {
    try {
      final res = await _client.get('/creator/$username');
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Full dashboard payload: active challenges, submission stats, gate
  /// progress, recent activity, aura balance. Response schema is
  /// Swagger-undocumented (generic envelope) — caller reads defensively.
  /// Prefer the confirmed-schema endpoints already used elsewhere
  /// (`AuthApiService.fetchAuraBalance`, `AuthApiService.fetchMyVideos`,
  /// `fetchDashboardSummary` below) for anything they already cover.
  Future<Map<String, dynamic>> fetchDashboard() async {
    try {
      final res = await _client.get('/creator/dashboard', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Compact operational status: `profileComplete`, `creatorPageLive`,
  /// `canUploadChallenge`, `challengeCount`, `followers`, `pageUrl`. Fully
  /// documented in Swagger, unlike most of this tag.
  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    try {
      final res = await _client.get('/creator/dashboard-summary', auth: true);
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Aggregated analytics: views/participants/aura earned/growth trends by
  /// challenge. Response schema is undocumented — caller reads defensively.
  Future<Map<String, dynamic>> fetchAnalytics() async {
    try {
      final res = await _client.get('/creator/analytics', auth: true);
      if (res['status'] != 'success') return {};
      return res['data'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }
}
