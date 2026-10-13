import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/auth_api_service.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ApiClient.httpClient = http.Client());

  group('requestOtp', () {
    test('reads validitySeconds/expiresAt and never a raw otp', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'message': 'OTP sent successfully.',
                'expiresAt': '2026-08-30T10:03:00.000Z',
                'validitySeconds': 180,
              },
            }),
            200,
          ));

      final res = await AuthApiService()
          .requestOtp(phone: '9876543210', countryCode: '+91');

      expect(res.validitySeconds, 180);
      expect(res.expiresAt, DateTime.utc(2026, 8, 30, 10, 3));
    });

    // Backend ADR 121: Message Central sends no new SMS while a code is live.
    test('reads resent:false and the backend message for a reused code', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'message':
                    'We already sent a code to this number. Please enter that code.',
                'validitySeconds': 212,
                'resent': false,
              },
            }),
            200,
          ));

      final res = await AuthApiService()
          .requestOtp(phone: '9876543210', countryCode: '+91');

      expect(res.resent, isFalse);
      expect(res.message, contains('already sent a code'));
      expect(res.validitySeconds, 212);
    });

    test('treats a response without resent as a fresh SMS', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
            jsonEncode({'status': 'success', 'data': {'validitySeconds': 180}}),
            200,
          ));

      final res = await AuthApiService()
          .requestOtp(phone: '9876543210', countryCode: '+91');

      expect(res.resent, isTrue);
    });

    test('defaults validitySeconds to 180 when the field is absent', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
            jsonEncode({'status': 'success', 'data': {}}),
            200,
          ));

      final res = await AuthApiService()
          .requestOtp(phone: '9876543210', countryCode: '+91');

      expect(res.validitySeconds, 180);
      expect(res.expiresAt, isNull);
    });

    test('throws the backend message on a 429 rate-limit', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'fail',
              'message': 'Please wait 58 seconds before requesting another OTP.',
            }),
            429,
          ));

      expect(
        () => AuthApiService()
            .requestOtp(phone: '9876543210', countryCode: '+91'),
        throwsA('Please wait 58 seconds before requesting another OTP.'),
      );
    });
  });
}
