import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Confirms whether Aura's backend is genuinely unreachable before the app
/// commits to showing a "couldn't reach Aura's servers" error off a single
/// failed request. Per the backend team's guidance: one failed request
/// isn't reliable evidence on its own (a lone dropped packet or transient
/// blip is common, especially on mobile networks) — ping a handful of
/// times, and only escalate to a second, smaller confirmation round (and
/// only trust *that* round) before actually calling it unreachable.
///
/// "Ping" here means a real HTTP round-trip to the backend, not ICMP —
/// there's no dedicated health-check endpoint (checked against the live
/// OpenAPI spec) and adding ICMP support would mean a new platform plugin
/// for no real benefit: for "can the app reach Aura's servers" any HTTP
/// response at all (even a 404) is equally valid proof of reachability, so
/// hitting the API's own base URL works without needing a special route.
class ConnectivityProbe {
  ConnectivityProbe._();

  static const _initialPings = 5;
  static const _confirmPings = 2;
  static const _pingTimeout = Duration(seconds: 3);

  // Its own overridable client (not ApiClient.httpClient, which is
  // @visibleForTesting for that class's own test suite specifically) so
  // tests can substitute a package:http/testing.dart MockClient here too.
  @visibleForTesting
  static http.Client httpClient = http.Client();

  /// Returns true only once repeated pings agree the backend really can't
  /// be reached. Returns false (treat it as a false alarm) as soon as
  /// there's decent evidence otherwise — either most of the first round
  /// succeeded, or any ping in the confirmation round got through.
  static Future<bool> confirmUnreachable() async {
    final firstRoundFailures = await _countFailures(_initialPings);
    // More than half the initial round succeeded — good enough evidence
    // the failure that triggered this check was a one-off blip, not a
    // real outage. No need to spend more time confirming.
    if (firstRoundFailures <= _initialPings ~/ 2) return false;

    // The initial round was mostly failures, which is suspicious enough to
    // run a second, smaller confirmation round — but a single success
    // there is still enough to call it a false alarm rather than
    // committing to "unreachable" off a run of bad luck.
    final confirmFailures = await _countFailures(_confirmPings);
    return confirmFailures == _confirmPings;
  }

  // Fired concurrently (not sequentially) so a round's wall-clock cost is
  // bounded by one _pingTimeout, not `count * _pingTimeout` — the user is
  // sitting on a loading spinner while this runs, so worst case for both
  // rounds combined should be seconds, not tens of seconds.
  static Future<int> _countFailures(int count) async {
    final results = await Future.wait(List.generate(count, (_) => _ping()));
    return results.where((reachable) => !reachable).length;
  }

  static Future<bool> _ping() async {
    try {
      await httpClient
          .get(Uri.parse(ApiConfig.baseUrl))
          .timeout(_pingTimeout);
      // Any response at all — even an error status — proves the server
      // was actually reached; only a thrown exception (timeout, socket
      // error, ...) means this particular ping failed.
      return true;
    } catch (_) {
      return false;
    }
  }
}
