import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';
import 'package:aura_app/shared/widgets/notification_bell_button.dart';

// Regression coverage for the header layout: @username and the Aura score
// pill sit side by side on one line, vertically centred with each other and
// with the compact notification bell.
//
// The bug this pins: the name group was `Spacer() + Flexible(Row(min))`.
// The Spacer stole half the free space, and a Flexible child of a
// MainAxisSize.min Row only gets what's left after the fixed children — so
// on a real phone with a large system font the scaled-up Aura pill filled
// that half and squeezed the @username to ~0px (still "found", invisible).
// The fix: one Expanded for the whole right side, aligned to its end.
//
// In its own file so it runs in a clean isolate: dashboard_test.dart pumps
// Dashboard twice already and leaks periodic timers (the 20s profile poll)
// that starve a third pump's event loop.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Tushar',
                'username': 'tushar',
                'auraPoints': 1240,
                'level': 3,
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
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  Future<void> pumpHeader(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    // uid FutureBuilder → postFrame → profile FutureBuilder.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('@username and the Aura score sit side by side', (tester) async {
    await pumpHeader(tester);

    expect(find.text('@tushar'), findsOneWidget,
        reason: 'header shows the @username once the profile loads');
    expect(find.text('1240'), findsOneWidget);

    // Same Row (side by side), not a Column (stacked).
    final nameRowFinder =
        find.ancestor(of: find.text('@tushar'), matching: find.byType(Row)).first;
    expect(find.descendant(of: nameRowFinder, matching: find.text('1240')),
        findsOneWidget,
        reason: 'the Aura score shares the @username\'s row');

    // That Row must NOT be MainAxisSize.min: a Flexible child of a min Row
    // only gets the space left over after the fixed children, so a scaled-up
    // Aura pill squeezed the @username to nothing on real phones. The fixed
    // layout uses a full-width (max) Row for the right side.
    expect(tester.widget<Row>(nameRowFinder).mainAxisSize, MainAxisSize.max,
        reason: 'the name/pill/bell row fills its slot rather than shrinking '
            'to its children (which starved the Flexible @username)');

    // Vertical centres line up — a stacked layout would put them ~20px apart.
    final nameCentre = tester.getCenter(find.text('@tushar')).dy;
    final scoreCentre = tester.getCenter(find.text('1240')).dy;
    expect((nameCentre - scoreCentre).abs(), lessThan(4.0));

    // The bell is the compact, margin-hugging variant.
    final bell = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(NotificationBellButton),
        matching: find.byType(IconButton),
      ),
    );
    expect(bell.padding, EdgeInsets.zero);
    expect(bell.alignment, Alignment.centerRight);
    expect(bell.constraints, const BoxConstraints(minWidth: 40, minHeight: 40));
  });
}
