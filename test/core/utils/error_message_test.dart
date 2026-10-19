import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:aura_app/core/utils/error_message.dart';

// Regression coverage: Dashboard's profile-load error screen used to show a
// wifi_off icon and the literal text "Failed to load profile." for *any*
// failure, including real backend errors that have nothing to do with
// connectivity — misleadingly looking like "no internet" even when the
// device is online and the backend just returned an error. Dashboard now
// picks its icon/copy via isNetworkError()/humanizeError(); these tests pin
// down that only genuinely connectivity-flavored exceptions get the network
// treatment, and everything else surfaces its real reason.
void main() {
  group('isNetworkError', () {
    test('is true for a SocketException (no connection)', () {
      expect(isNetworkError(const SocketException('Network is unreachable')),
          isTrue);
    });

    test('is true for a TimeoutException (request timed out)', () {
      expect(isNetworkError(TimeoutException('timed out')), isTrue);
    });

    test('is true for http.ClientException wrapping a socket failure', () {
      expect(
          isNetworkError(
              http.ClientException('Failed host lookup: backend.example')),
          isTrue);
    });

    // Regression (2026-10-19): the backend restarted mid-request and the create
    // screen showed "ClientConnection closed before full header was received,
    // uri=http://localhost:3000/..." instead of a readable message.
    test('is true when the connection drops mid-request', () {
      expect(
          isNetworkError(http.ClientException(
              'Connection closed before full header was received',
              Uri.parse('http://localhost:3000/api/v1/creator/challenge/categories'))),
          isTrue);
      expect(isNetworkError(const SocketException('Connection reset by peer')), isTrue);
      expect(isNetworkError(const SocketException('Broken pipe')), isTrue);
      expect(
          humanizeError(http.ClientException('Connection closed before full header was received')),
          "Couldn't reach Aura's servers. Please check your connection and try again.");
    });

    test('is false for a real backend error message', () {
      expect(isNetworkError(Exception('Internal server error')), isFalse);
    });

    test('is false for a plain "Failed to load profile" exception', () {
      expect(isNetworkError(Exception('Failed to load profile')), isFalse);
    });
  });

  group('humanizeError', () {
    test('gives the generic connectivity message for network exceptions',
        () {
      expect(
        humanizeError(const SocketException('Network is unreachable')),
        "Couldn't reach Aura's servers. Please check your connection and try again.",
      );
    });

    test('preserves the real message for non-network exceptions', () {
      expect(
        humanizeError(Exception('Internal server error')),
        'Internal server error',
      );
    });
  });
}
