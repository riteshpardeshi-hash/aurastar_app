import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:aura_app/core/services/leaderboard_consent_service.dart';
import 'package:aura_app/features/account/screens/settings_screen.dart';

// Apple 1.2: the app must publish a working support contact. Settings shows a
// "Contact Support" row that opens the mail app at info@onadsgroup.com (the
// contact in the hosted Privacy Policy) — the Help sheet used to name a
// non-existent support@aura.app.
void main() {
  // Settings' leaderboard toggle loads GET /profile when consent isn't known yet;
  // seed it so the toggle doesn't leave a pending storage-read timer behind.
  setUp(
    () => LeaderboardConsentService.instance.updateFromProfile({
      'leaderboardConsent': {'status': 'granted'},
    }),
  );
  tearDown(LeaderboardConsentService.instance.reset);

  testWidgets('Contact Support opens a mail to info@onadsgroup.com', (
    tester,
  ) async {
    final launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();

    final row = find.text('Contact Support');
    await tester.scrollUntilVisible(row, 200);
    expect(find.text('info@onadsgroup.com'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      launcher.launchedUrls.single,
      startsWith('mailto:info@onadsgroup.com'),
    );
  });

  testWidgets('the Help sheet no longer names support@aura.app', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();

    final help = find.text('Help & Rules');
    await tester.scrollUntilVisible(help, 200);
    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(find.textContaining('support@aura.app'), findsNothing);
    expect(find.textContaining('info@onadsgroup.com'), findsOneWidget);
  });
}

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}
