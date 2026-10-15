import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/config/api_config.dart';
import 'package:aura_app/core/services/leaderboard_consent_service.dart';
import 'package:aura_app/features/account/screens/settings_screen.dart';

// ADR 036 (2026-10-15): shipped builds showed Settings → Debug → "API server", letting any user
// repoint the app at another backend (and a saved URL survived app updates). Builds that go to
// users must only ever talk to production.
void main() {
  setUp(() => LeaderboardConsentService.instance
      .updateFromProfile({'leaderboardConsent': {'status': 'granted'}}));
  tearDown(LeaderboardConsentService.instance.reset);

  testWidgets('Settings has no API-server picker and no debug preview tile', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete Account'), 300);

    expect(find.text('API server'), findsNothing);
    expect(find.text('Preview: Video Rejected'), findsNothing);
    expect(find.textContaining(ApiConfig.production), findsNothing);
  });

  test('a backend URL saved by an older build is ignored — the app uses production', () async {
    SharedPreferences.setMockInitialValues({'api_base_url_override': 'http://192.168.0.5:3000/api/v1'});
    await SharedPreferences.getInstance();
    expect(ApiConfig.baseUrl, ApiConfig.production);
    expect(ApiConfig.production, 'http://144.91.79.237:3786/api/v1');
  });
}
