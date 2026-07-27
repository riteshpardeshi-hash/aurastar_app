import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';
import 'package:aura_app/shared/widgets/avatar_widget.dart';

// Regression coverage: the top-bar avatar next to the user's name always
// rendered the display-name initial in a gradient circle — it never
// received photoUrl at all, even though _fetchDashboardProfile already
// correctly reads it from GET /profile's `avatar` field and the bottom-nav
// profile tab right next to it already renders it correctly via
// AvatarWidget. A user who set a profile photo saw it on My Account and in
// the bottom nav, but the top header still showed just their initial.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('the top-bar avatar renders the real profile photo, not just '
      "the display name's initial", (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Tushar',
                'avatar': 'https://example.com/avatar.jpg',
                'auraPoints': 0,
                'level': 1,
                'tier': 'rookie',
                'isProfileComplete': true,
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    // Dashboard resolves in stages: a FutureBuilder for the user id, then a
    // postFrameCallback that kicks off the profile FutureBuilder. Pump
    // through each stage before letting real (even if mocked) network calls
    // settle via runAsync.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    // Deliberately no further pump/runAsync after this: once AvatarWidget is
    // built with the right photoUrl, that's the regression this test cares
    // about — letting its Image.network actually attempt to load risks the
    // test process reaching out over a real socket.

    // Both the top-bar avatar AND the bottom-nav profile-tab avatar render
    // via AvatarWidget. The bottom nav already correctly received photoUrl
    // before this fix — asserting on "any" AvatarWidget wouldn't distinguish
    // the fixed header from the always-correct bottom nav, so require both
    // to have it (2), not just one.
    final withRealPhoto = tester
        .widgetList<AvatarWidget>(find.byType(AvatarWidget))
        .where((w) => w.photoUrl == 'https://example.com/avatar.jpg');
    expect(withRealPhoto.length, 2,
        reason: 'both the top-bar avatar and the bottom-nav avatar must '
            'receive the real photo URL — the top bar used to be hardcoded '
            "to the display name's initial regardless of photoUrl");
  });
}
