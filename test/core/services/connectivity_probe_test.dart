import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/connectivity_probe.dart';

// Regression coverage: Dashboard used to show "Couldn't reach Aura's
// servers" off a single failed request, which users reported seeing even
// on a strong connection — a lone dropped packet or transient blip was
// enough to trigger it. Per the backend team's guidance, ConnectivityProbe
// now confirms via repeated pings before that verdict is trusted: a false
// alarm (most of the first round succeeds) reports reachable; only a
// persistent failure across both a first round and a second confirmation
// round reports genuinely unreachable.
void main() {
  tearDown(() {
    ConnectivityProbe.httpClient = http.Client();
  });

  test('reports reachable when the server responds, even with an error '
      'status', () async {
    ConnectivityProbe.httpClient = MockClient((request) async {
      return http.Response('not found', 404);
    });

    expect(await ConnectivityProbe.confirmUnreachable(), isFalse,
        reason: 'any real HTTP response — even a 404 — proves the server '
            'was actually reached');
  });

  test('reports reachable (false alarm) when only a minority of the first '
      'round fails', () async {
    var calls = 0;
    ConnectivityProbe.httpClient = MockClient((request) async {
      calls++;
      // Only the very first ping fails; the rest of that round succeeds.
      if (calls == 1) throw Exception('socket error');
      return http.Response('ok', 200);
    });

    expect(await ConnectivityProbe.confirmUnreachable(), isFalse,
        reason: 'a lone failed ping among an otherwise-healthy round must '
            'not be enough to declare the server unreachable — this is '
            'exactly the single-blip false positive being fixed');
  });

  test('reports unreachable only when both the initial round and the '
      'confirmation round persistently fail', () async {
    ConnectivityProbe.httpClient = MockClient((request) async {
      throw Exception('socket error');
    });

    expect(await ConnectivityProbe.confirmUnreachable(), isTrue,
        reason: 'a real, persistent outage — every single ping across both '
            'rounds failing — must still be reported as unreachable');
  });

  test('a single success in the confirmation round is enough to call it a '
      'false alarm', () async {
    var calls = 0;
    ConnectivityProbe.httpClient = MockClient((request) async {
      calls++;
      // Fail the whole first round (calls 1-5), then let the confirmation
      // round (calls 6-7) succeed.
      if (calls <= 5) throw Exception('socket error');
      return http.Response('ok', 200);
    });

    expect(await ConnectivityProbe.confirmUnreachable(), isFalse,
        reason: 'the confirmation round exists precisely to catch a first '
            'round that failed by bad luck — any success there must win');
  });
}
