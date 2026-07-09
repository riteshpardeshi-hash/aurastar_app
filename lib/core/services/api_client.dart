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
  }) async {
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    debugPrint('[API] POST ${ApiConfig.baseUrl}$path');
    debugPrint('[API] Body: ${jsonEncode(body)}');
    var res = await http.post(_uri(path), headers: headers, body: jsonEncode(body));
    debugPrint('[API] ${res.statusCode} ${res.body}');
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await http.post(_uri(path), headers: headers, body: jsonEncode(body));
      debugPrint('[API] Retry ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    var headers = await _authedHeaders();
    var res = await http.patch(_uri(path), headers: headers, body: jsonEncode(body));
    if (res.statusCode == 401 && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await http.patch(_uri(path), headers: headers, body: jsonEncode(body));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    var headers = await _authedHeaders();
    var res = await http.put(_uri(path), headers: headers, body: jsonEncode(body));
    if (res.statusCode == 401 && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await http.put(_uri(path), headers: headers, body: jsonEncode(body));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    var res = await http.get(_uri(path), headers: headers);
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await http.get(_uri(path), headers: headers);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path, {bool auth = false}) async {
    var headers = auth ? await _authedHeaders() : _baseHeaders;
    var res = await http.delete(_uri(path), headers: headers);
    if (res.statusCode == 401 && auth && await _tryRefresh()) {
      headers = await _authedHeaders();
      res = await http.delete(_uri(path), headers: headers);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> uploadToS3(
    String uploadUrl,
    File file, {
    void Function(double progress)? onProgress,
    String contentType = 'video/mp4',
  }) async {
    final fileLength = await file.length();
    final client = http.Client();
    try {
      final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
      request.headers['Content-Type'] = contentType;
      request.contentLength = fileLength;

      int sent = 0;
      file.openRead().listen(
        (chunk) {
          request.sink.add(chunk);
          sent += chunk.length;
          if (fileLength > 0) onProgress?.call(sent / fileLength);
        },
        onDone: request.sink.close,
        onError: request.sink.addError,
      );

      final response = await client.send(request);
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('S3 upload failed: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<bool> _tryRefresh() async {
    final rt = await refreshToken;
    if (rt == null) return false;
    try {
      final res = await http.post(
        _uri('/auth/refresh'),
        headers: _baseHeaders,
        body: jsonEncode({'refreshToken': rt}),
      );
      if (res.statusCode == 200) {
        final data =
            (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
        await _storage.write(key: _kAccess, value: data['accessToken'] as String);
        await _storage.write(key: _kRefresh, value: data['refreshToken'] as String);
        return true;
      }
    } catch (_) {}
    await clearSession();
    return false;
  }
}
