import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

import 'crash_reporter.dart';

/// Thin wrapper over Firebase Analytics (Google Analytics for Firebase).
///
/// Every method is fire-and-forget and never throws: analytics must not be
/// able to break a screen, and Firebase may legitimately be uninitialised
/// (the boot-time `Firebase.initializeApp` is bounded by a timeout and its
/// failure is swallowed, and unit tests never initialise it). See ADR 022.
///
/// Callers pass only opaque ids and coarse enums — never phone numbers,
/// names, or other PII.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  factory AnalyticsService() => instance;

  /// Test seam: receives every event instead of Firebase when set.
  @visibleForTesting
  static void Function(String name, Map<String, Object>? params)? sink;

  static FirebaseAnalytics? _fa;
  static final Map<String, String?> _userProps = {};

  FirebaseAnalytics? get _analytics {
    try {
      return _fa ??= FirebaseAnalytics.instance;
    } catch (_) {
      return null; // Firebase not initialised
    }
  }

  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    final s = sink;
    if (s != null) {
      s(name, params);
      return;
    }
    try {
      await _analytics?.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics event "$name" failed: $e');
    }
  }

  Future<void> logScreen(String screenName) {
    CrashReporter.log('screen: $screenName'); // breadcrumb for crash reports
    return logEvent('screen_view', {
      'screen_name': screenName,
      'screen_class': screenName,
    });
  }

  /// Ties events to the backend user id (opaque). Pass null on logout.
  Future<void> setUserId(String? id) async {
    // A different account must not inherit the previous one's properties.
    if (id == null) _userProps.clear();
    // Crash reports carry the same opaque id.
    CrashReporter.setUserId(id);
    final s = sink;
    if (s != null) {
      s('set_user_id', id == null ? null : {'id': id});
      return;
    }
    try {
      await _analytics?.setUserId(id: id);
    } catch (e) {
      debugPrint('Analytics setUserId failed: $e');
    }
  }

  /// User-scoped dimension (e.g. `user_level`, `account_type`). Firebase
  /// allows 25 per project and values up to 36 chars.
  Future<void> setUserProperty(String name, String? value) async {
    // Callers re-assert on every profile poll; only forward real changes.
    if (_userProps.containsKey(name) && _userProps[name] == value) return;
    _userProps[name] = value;
    final s = sink;
    if (s != null) {
      s('set_user_property', {'name': name, 'value': value ?? ''});
      return;
    }
    try {
      await _analytics?.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('Analytics setUserProperty "$name" failed: $e');
    }
  }

  Future<void> logRecordingStarted(String challengeId) =>
      logEvent('recording_started', {'challenge_id': challengeId});

  Future<void> logRecordingCancelled(String challengeId, int secondsRecorded) =>
      logEvent('recording_cancelled', {
        'challenge_id': challengeId,
        'seconds_recorded': secondsRecorded,
      });

  Future<void> logUploadStarted(String challengeId, {int? fileSizeBytes}) =>
      logEvent('upload_started', {
        'challenge_id': challengeId,
        if (fileSizeBytes != null) 'file_size': fileSizeBytes,
      });

  Future<void> logUploadSucceeded(String challengeId, {required int durationMs}) =>
      logEvent('upload_succeeded', {
        'challenge_id': challengeId,
        'duration_ms': durationMs,
      });

  /// [stage] is presign | upload | submission; [reason] is a coarse bucket
  /// (network | timeout | rejected | other) — never the raw error text.
  Future<void> logUploadFailed(
    String challengeId, {
    required String stage,
    required String reason,
  }) =>
      logEvent('upload_failed', {
        'challenge_id': challengeId,
        'stage': stage,
        'reason': reason,
      });

  Future<void> logSubmissionStatus({
    required String challengeId,
    required String status,
    required int score,
    required int points,
  }) =>
      logEvent('submission_status_changed', {
        'challenge_id': challengeId,
        'status': status,
        'score': score,
        'points': points,
        'reviewer': 'ai',
      });

  Future<void> logPointsAwarded({
    required String challengeId,
    required int amount,
  }) =>
      logEvent('points_awarded', {
        'amount': amount,
        'source_type': 'challenge_score',
        'source_id': challengeId,
      });

  Future<void> logLevelUp({int? toLevel}) =>
      logEvent('level_up', {if (toLevel != null) 'level': toLevel});

  Future<void> logLogin(String method) =>
      logEvent('login', {'method': method});

  Future<void> logSignUp(String method) =>
      logEvent('sign_up', {'method': method});

  Future<void> logLogout() => logEvent('logout');

  Future<void> logAccountDeletionRequested() =>
      logEvent('account_deletion_requested');

  /// [source] is where the user came from (home, search, deep_link, ...);
  /// [ownerType] is the challenge's `sourceType` and [ownerId] its
  /// `creatorId` ('system' for platform challenges), when known.
  Future<void> logChallengeView(
    String challengeId, {
    String source = 'unknown',
    String? ownerType,
    String? ownerId,
  }) =>
      logEvent('challenge_view', {
        'challenge_id': challengeId,
        'source': source,
        if (ownerType != null && ownerType.isNotEmpty) 'owner_type': ownerType,
        if (ownerId != null && ownerId.isNotEmpty) 'owner_id': ownerId,
      });

  Future<void> logShare({
    required String contentType,
    String? itemId,
    String? method,
  }) =>
      logEvent('share', {
        'content_type': contentType,
        if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
        if (method != null) 'method': method,
      });

  Future<void> logBrandPageView(String brandId, String source) =>
      logEvent('brand_page_view', {'brand_id': brandId, 'source': source});

  Future<void> logProfileView(String profileId, String source) =>
      logEvent('profile_view', {'profile_id': profileId, 'source': source});

  Future<void> logExploreBrandsClick() => logEvent('explore_brands_click');

  Future<void> logAuraCreatorJoinClick(String source) =>
      logEvent('aura_creator_join_click', {'source': source});

  Future<void> logCenterFabClick() => logEvent('center_fab_click');

  /// [step] is a stable name (profile, city, interests); [index] its order.
  Future<void> logOnboardingStep(String step, int index) =>
      logEvent('onboarding_step', {'step': step, 'step_index': index});

  /// GA4's recommended `search` event. The term is truncated to Firebase's
  /// 100-char param limit.
  Future<void> logSearch(String term, {required int results, String? type}) {
    final t = term.trim();
    return logEvent('search', {
      'search_term': t.length > 100 ? t.substring(0, 100) : t,
      'results': results,
      if (type != null) 'filter': type,
    });
  }

  /// [source]: organic | push | deeplink.
  Future<void> logAppOpen(String source) =>
      logEvent('app_open', {'source': source});

  Future<void> logDeepLinkOpen({required String target, String? id}) =>
      logEvent('deeplink_open', {
        'target': target,
        if (id != null && id.isNotEmpty) 'link_id': id,
      });

  Future<void> logCouponClaimed(String couponId) =>
      logEvent('coupon_claimed', {'coupon_id': couponId});

  Future<void> logFollow({
    required String targetId,
    required String targetType,
    required bool following,
  }) =>
      logEvent(following ? 'follow' : 'unfollow',
          {'target_id': targetId, 'target_type': targetType});

  Future<void> logSubmissionUploaded(String challengeId) =>
      logEvent('submission_uploaded', {'challenge_id': challengeId});
}

/// Reports `screen_view` for pushed routes that carry a
/// `RouteSettings.name`. The app uses unnamed `MaterialPageRoute`s almost
/// everywhere, so unnamed routes are skipped rather than logged as noise; the
/// four bottom-nav tabs (an `IndexedStack`, not routes) are reported by
/// `MainShell` directly.
class AnalyticsRouteObserver extends NavigatorObserver {
  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty || name == '/') return;
    AnalyticsService().logScreen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);
}
