import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/create_creator_profile_screen.dart';

// Any player can apply to become a creator (backend ADR 140): no Aura wall, and the screen
// follows the admin's review — under review, changes asked for (prefilled form + the note),
// or not approved (reason + apply again).
http.Response _ok(Object data) =>
    http.Response(jsonEncode({'status': 'success', 'data': data}), 200);

void _mockApi(Map<String, dynamic> setupStatus, {Map<String, dynamic>? page}) {
  ApiClient.httpClient = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/creator/setup-status')) return _ok(setupStatus);
    if (path.endsWith('/creator/categories')) {
      return _ok({
        'categories': ['Dance', 'Gaming'],
      });
    }
    if (path.endsWith('/creator/page') && request.method == 'GET') {
      return _ok({'profile': page});
    }
    if (path.endsWith('/creator/check-username')) {
      return _ok({'available': true, 'suggestions': []});
    }
    return http.Response(jsonEncode({'status': 'fail'}), 404);
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: CreateCreatorProfileScreen()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('a new player sees the application form, no Aura wall', (
    tester,
  ) async {
    _mockApi({'eligible': true, 'currentStep': 'ELIGIBLE'});
    await _pump(tester);

    expect(find.text('Your application'), findsOneWidget);
    expect(find.text('Submit Application'), findsOneWidget);
    expect(find.textContaining('Aura to go'), findsNothing);
  });

  testWidgets('a pending application shows it is under review', (tester) async {
    _mockApi({
      'eligible': true,
      'currentStep': 'PENDING_REVIEW',
      'appliedAt': '2026-11-19T10:00:00.000Z',
    });
    await _pump(tester);

    expect(find.text('Application under review'), findsOneWidget);
    expect(find.text('Submit Application'), findsNothing);
  });

  testWidgets(
    'changes requested: the note is shown and the form is prefilled',
    (tester) async {
      _mockApi(
        {
          'eligible': true,
          'currentStep': 'CHANGES_REQUESTED',
          'changesRequestedNote': 'Add your Instagram link',
        },
        page: {
          'displayName': 'Test Dancer',
          'username': 'testdancer',
          'bio': 'I dance',
          'category': 'Dance',
          'socialLinks': {},
        },
      );
      await _pump(tester);

      expect(find.text('Add your Instagram link'), findsOneWidget);
      expect(find.text('Test Dancer'), findsOneWidget);
      expect(find.text('testdancer'), findsOneWidget);
      expect(find.text('Resubmit Application'), findsOneWidget);
    },
  );

  testWidgets('rejected: shows the reason and lets them apply again', (
    tester,
  ) async {
    _mockApi(
      {
        'eligible': true,
        'currentStep': 'REJECTED',
        'rejectedReason': 'Not enough original content yet',
      },
      page: {
        'displayName': 'Test Dancer',
        'username': 'testdancer',
        'socialLinks': {},
      },
    );
    await _pump(tester);

    expect(find.text('Not approved this time'), findsOneWidget);
    expect(find.text('Not enough original content yet'), findsOneWidget);

    await tester.tap(find.text('Update & apply again'));
    await tester.pumpAndSettle();
    expect(find.text('Resubmit Application'), findsOneWidget);
  });

  testWidgets('rejected without a reason shows no reason card', (tester) async {
    _mockApi({
      'eligible': true,
      'currentStep': 'REJECTED',
      'rejectedReason': null,
    });
    await _pump(tester);

    expect(find.text('Not approved this time'), findsOneWidget);
    expect(find.text('Reason from our team'), findsNothing);
  });
}
