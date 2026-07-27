import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/auth/screens/phone_auth_screen.dart';

// Regression coverage: a network failure sending the OTP used to show the
// raw exception text (e.g. "TimeoutException after 0:00:15.000000: ...")
// directly in the snackbar via `_snack(e.toString())`, instead of a message
// a user could act on. Routed through the existing humanizeError() helper
// (already used elsewhere for exactly this) instead.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('a network timeout sending the OTP shows a humanized message, '
      'not raw exception text', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        throw TimeoutException(
            'Future not completed', const Duration(seconds: 15));
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: PhoneAuthScreen()));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('TimeoutException'), findsNothing,
        reason: 'the raw Dart exception text must never reach the user');
    expect(
      find.textContaining('No internet connection'),
      findsOneWidget,
      reason: 'humanizeError() should turn a timeout into an actionable, '
          'friendly message',
    );
  });
}
