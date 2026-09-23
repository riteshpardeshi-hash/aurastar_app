import 'package:aura_app/core/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AnalyticsService.sink = null);

  test('never throws when Firebase is not initialised', () async {
    // No sink and no Firebase.initializeApp in unit tests: must no-op.
    await AnalyticsService().logEvent('anything', {'a': 1});
    await AnalyticsService().setUserId('u1');
    await AnalyticsService().setUserId(null);
  });

  test('typed helpers emit the expected event names and params', () async {
    final seen = <String, Map<String, Object>?>{};
    AnalyticsService.sink = (n, p) => seen[n] = p;

    await AnalyticsService().logLogin('phone');
    await AnalyticsService().logSignUp('phone');
    await AnalyticsService().logChallengeView('c1');
    await AnalyticsService().logShare(contentType: 'challenge', itemId: 'c1');
    await AnalyticsService().logSubmissionUploaded('c1');

    expect(seen['login'], {'method': 'phone'});
    expect(seen['sign_up'], {'method': 'phone'});
    expect(seen['challenge_view'], {'challenge_id': 'c1', 'source': 'unknown'});
    expect(seen['share'], {'content_type': 'challenge', 'item_id': 'c1'});
    expect(seen['submission_uploaded'], {'challenge_id': 'c1'});
  });

  test('route observer logs named routes only', () {
    final names = <String>[];
    AnalyticsService.sink = (n, p) {
      if (n == 'screen_view') names.add(p!['screen_name']! as String);
    };
    final o = AnalyticsRouteObserver();
    Route<void> r(String? name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name), builder: (_) => const SizedBox());

    o.didPush(r('challenge_detail'), null);
    o.didPush(r(null), null);
    o.didPush(r('/'), null);

    expect(names, ['challenge_detail']);
  });

  test('funnel helpers emit sheet-aligned names and params', () async {
    final seen = <String, Map<String, Object>?>{};
    AnalyticsService.sink = (n, p) => seen[n] = p;
    final a = AnalyticsService();

    await a.logRecordingStarted('c1');
    await a.logRecordingCancelled('c1', 7);
    await a.logUploadStarted('c1', fileSizeBytes: 100);
    await a.logUploadSucceeded('c1', durationMs: 900);
    await a.logUploadFailed('c1', stage: 'upload', reason: 'network');
    await a.logSubmissionStatus(
        challengeId: 'c1', status: 'approved', score: 80, points: 80);
    await a.logPointsAwarded(challengeId: 'c1', amount: 80);
    await a.logLevelUp(toLevel: 2);
    await a.setUserProperty('user_level', '2');
    await a.setUserProperty('user_level', '2'); // unchanged -> not re-sent
    seen.remove('set_user_property');
    await a.setUserProperty('user_level', '2');
    expect(seen.containsKey('set_user_property'), isFalse);
    await a.setUserProperty('user_level', '3');

    expect(seen['recording_cancelled'],
        {'challenge_id': 'c1', 'seconds_recorded': 7});
    expect(seen['upload_started'], {'challenge_id': 'c1', 'file_size': 100});
    expect(seen['upload_failed'],
        {'challenge_id': 'c1', 'stage': 'upload', 'reason': 'network'});
    expect(seen['submission_status_changed']!['status'], 'approved');
    expect(seen['points_awarded']!['amount'], 80);
    expect(seen['level_up'], {'level': 2});
    expect(seen['set_user_property'], {'name': 'user_level', 'value': '3'});
    expect(seen['recording_started'], {'challenge_id': 'c1'});
    expect(seen['upload_succeeded']!['duration_ms'], 900);
  });

  test('batch 1 helpers emit sheet-aligned names and params', () async {
    final seen = <String, Map<String, Object>?>{};
    AnalyticsService.sink = (n, p) => seen[n] = p;
    final a = AnalyticsService();

    await a.logChallengeView('c1',
        source: 'search', ownerType: 'brand', ownerId: 'b1');
    await a.logBrandPageView('b1', 'explore_brands');
    await a.logProfileView('u1', 'search');
    await a.logAuraCreatorJoinClick('profile_banner');
    await a.logOnboardingStep('city', 2);
    await a.logAppOpen('push');
    await a.logDeepLinkOpen(target: 'challenge', id: 'c1');
    await a.logCouponClaimed('cp1');
    await a.logFollow(targetId: 'u1', targetType: 'brand', following: true);
    await a.logSearch('  x' * 60, results: 3, type: 'all');

    expect(seen['challenge_view'], {
      'challenge_id': 'c1',
      'source': 'search',
      'owner_type': 'brand',
      'owner_id': 'b1',
    });
    expect(seen['brand_page_view'], {'brand_id': 'b1', 'source': 'explore_brands'});
    expect(seen['profile_view'], {'profile_id': 'u1', 'source': 'search'});
    expect(seen['aura_creator_join_click'], {'source': 'profile_banner'});
    expect(seen['onboarding_step'], {'step': 'city', 'step_index': 2});
    expect(seen['app_open'], {'source': 'push'});
    expect(seen['deeplink_open'], {'target': 'challenge', 'link_id': 'c1'});
    expect(seen['coupon_claimed'], {'coupon_id': 'cp1'});
    expect(seen['follow'], {'target_id': 'u1', 'target_type': 'brand'});
    expect(seen.containsKey('unfollow'), isFalse);
    expect((seen['search']!['search_term']! as String).length, lessThanOrEqualTo(100));
    expect(seen['search']!['results'], 3);
  });

  test('challenge_view omits blank owner fields and defaults source', () async {
    Map<String, Object>? got;
    AnalyticsService.sink = (n, p) => got = p;
    await AnalyticsService().logChallengeView('c1', ownerType: '', ownerId: null);
    expect(got, {'challenge_id': 'c1', 'source': 'unknown'});
  });
}
