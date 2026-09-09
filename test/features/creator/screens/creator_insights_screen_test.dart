import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/creator_insights_screen.dart';

// Regression: GET /creator/insights/filter-options returns each option as a
// `{value, label}` object, but the Performance tab stringified the whole entry
// (`e.toString()`) into the chip list — so the date-range and metric chips
// literally read "{value: today, label: Today}" / "{value: views, label:
// Views}". They must show the label text instead.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;

      if (request.method == 'GET' &&
          path.endsWith('/creator/insights/filter-options')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'dateRanges': [
                {'value': 'today', 'label': 'Today'},
                {'value': '7d', 'label': 'Last 7 Days'},
                {'value': '30d', 'label': 'Last 30 Days'},
              ],
              'metrics': [
                {'value': 'views', 'label': 'Views'},
                {'value': 'participants', 'label': 'Participants'},
              ],
            },
          }),
          200,
        );
      }

      // Performance overview + chart: empty is fine, the tab renders zeros.
      return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('Performance filter chips show labels, not the raw {value,label} object',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreatorInsightsScreen()));
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // The bug: raw stringified maps leaking into the UI.
    expect(find.textContaining('{value:'), findsNothing,
        reason: 'filter options must be unwrapped to their value/label, not '
            'rendered as a stringified Map');

    // The fix: backend-supplied labels on the chips.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Last 7 Days'), findsOneWidget);
    expect(find.text('Views'), findsWidgets); // chip + section heading
    expect(find.text('Participants'), findsWidgets); // chip + stat card
  });
}
