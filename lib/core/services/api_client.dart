import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'api_access_token';
  static const _kRefresh = 'api_refresh_token';
  static const _kUserId = 'api_user_id';

  // Overridable so tests can substitute a package:http/testing.dart
  // MockClient instead of hitting the network.
  @visibleForTesting
  static http.Client httpClient = http.Client();

  // Fired when an authenticated call gets a 401 and the refresh token can't
  // salvage it — i.e. the session is genuinely dead (expired/revoked), not a
  // transient network blip. A 401 only happens after the backend was
  // actually reached, so this can never be confused with connectivity
  // failures. Callers used to swallow this into a generic null/error and
  // leave the user stuck on a dead screen with no valid credentials to
  // retry with; listening for this and routing back to login is the only
  // way out.
  static final _sessionExpired = StreamController<void>.broadcast();
  static Stream<void> get onSessionExpired => _sessionExpired.stream;

  // No timeout meant a stalled connection (common on flaky mobile networks)
  // left callers awaiting forever — e.g. Future.wait([...]) in
  // MyAccountScreen._loadAll() never resolving, so the screen stayed stuck
  // on its loading spinner permanently instead of failing gracefully into
  // the try/catch every service method already has.
  static const _timeout = Duration(seconds: 15);

  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);
  Future<String?> get userId => _storage.read(key: _kUserId);

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: accessToken),
      _storage.write(key: _kRefresh, value: refreshToken),
      _storage.write(key: _kUserId, value: userId),
    ]);
  }

  Future<void> clearSession() => _storage.deleteAll();

  Future<bool> isLoggedIn() async {
    final token = await accessToken;
    return token != null && token.isNotEmpty;
  }

  Map<String, String> get _baseHeaders => const {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      };

  Future<Map<String, String>> _authedHeaders() async {
    final token = await accessToken;
    return {
      ..._baseHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
    // Overridable per-call: most POSTs are ordinary CRUD and fit well
    // within _timeout, but a few (e.g. create-submission) are documented as
    // running a synchronous multi-step AI pipeline server-side and need
    // more room before a slow-but-legitimate response gets misread as a
    // dead connection.
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _timeout;
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    debugPrint('[API] POST ${ApiConfig.baseUrl}$path');
    debugPrint('[API] Body: ${jsonEncode(body)}');
    var res = await httpClient
        .post(_uri(path), headers: headers, body: jsonEncode(body))
        .timeout(effectiveTimeout);
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await httpClient
          .post(_uri(path), headers: headers, body: jsonEncode(body))
          .timeout(effectiveTimeout);
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    var headers = await _authedHeaders();
    debugPrint('[API] PATCH ${ApiConfig.baseUrl}$path');
    debugPrint('[API] Body: ${jsonEncode(body)}');
    var res = await httpClient
        .patch(_uri(path), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await httpClient
          .patch(_uri(path), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    var headers = await _authedHeaders();
    debugPrint('[API] PUT ${ApiConfig.baseUrl}$path');
    debugPrint('[API] Body: ${jsonEncode(body)}');
    var res = await httpClient
        .put(_uri(path), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await httpClient
          .put(_uri(path), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    debugPrint('[API] GET ${ApiConfig.baseUrl}$path');
    var res =
        await httpClient.get(_uri(path), headers: headers).timeout(_timeout);
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res =
          await httpClient.get(_uri(path), headers: headers).timeout(_timeout);
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = false}) async {
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    debugPrint('[API] DELETE ${ApiConfig.baseUrl}$path');
    var res = await httpClient
        .delete(_uri(path), headers: headers)
        .timeout(_timeout);
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await httpClient
          .delete(_uri(path), headers: headers)
          .timeout(_timeout);
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // No overall cap here — legitimately slow (but still moving) uploads on a
  // weak connection shouldn't be killed mid-transfer. Instead this is an
  // *idle* timeout: it resets on every chunk actually written, so it only
  // fires when the connection has genuinely stalled (e.g. dropped mid-
  // upload), turning what used to be an indefinite hang — the "Uploading…"
  // screen has no cancel/retry button — into a caught exception the caller
  // can recover from.
  static const _uploadIdleTimeout = Duration(seconds: 20);

  Future<void> uploadToS3(
    String uploadUrl,
    File file, {
    void Function(double progress)? onProgress,
    String contentType = 'video/mp4',
  }) async {
    final fileLength = await file.length();
    final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
    request.headers['Content-Type'] = contentType;
    request.contentLength = fileLength;

    Timer? idleTimer;
    void armIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(_uploadIdleTimeout, () {
        request.sink.addError(TimeoutException(
            'Upload stalled — no data sent for ${_uploadIdleTimeout.inSeconds}s'));
      });
    }

    int sent = 0;
    armIdleTimer();
    final sub = file.openRead().listen(
      (chunk) {
        request.sink.add(chunk);
        sent += chunk.length;
        if (fileLength > 0) onProgress?.call(sent / fileLength);
        armIdleTimer();
      },
      onDone: () {
        idleTimer?.cancel();
        request.sink.close();
      },
      onError: (Object e) {
        idleTimer?.cancel();
        request.sink.addError(e);
      },
    );

    try {
      final response = await httpClient.send(request);
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('S3 upload failed: ${response.statusCode}');
      }
    } finally {
      idleTimer?.cancel();
      await sub.cancel();
    }
  }

  // The backend rotates refresh tokens on every use (single-use — the
  // submitted token is revoked immediately, see docs/api/openapi.yaml on
  // /auth/refresh). If several authed calls race a 401 at once (e.g.
  // Dashboard's Future.wait of 3 calls right as the access token expires),
  // each independently reading and POSTing the refresh token would mean only
  // the first one lands — the rest replay a now-revoked token, get a 401
  // back, and clearSession() wipes out the valid pair the first call just
  // saved. Dedupe so only one refresh actually hits the network per expiry;
  // the rest await its result and retry with the token it obtained.
  Future<bool>? _refreshInFlight;

  Future<bool> _tryRefresh() {
    return _refreshInFlight ??=
        _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final rt = await refreshToken;
    if (rt != null) {
      try {
        final res = await httpClient
            .post(
              _uri('/auth/refresh'),
              headers: _baseHeaders,
              body: jsonEncode({'refreshToken': rt}),
            )
            .timeout(_timeout);
        if (res.statusCode == 200) {
          final data =
              (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
          await _storage.write(key: _kAccess, value: data['accessToken'] as String);
          await _storage.write(key: _kRefresh, value: data['refreshToken'] as String);
          return true;
        }
      } catch (_) {}
    }
    await clearSession();
    _sessionExpired.add(null);
    return false;
  }
}
