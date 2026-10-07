import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';

/// A recorded request the screens/service sent.
class SentRequest {
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, dynamic>? body;

  SentRequest(this.method, this.path, this.query, this.body);

  @override
  String toString() => '$method $path ${body ?? ''}';
}

typedef FakeHandler = http.Response Function(SentRequest req);

/// In-memory stand-in for the backend's `/api/v1/creator/ai-*` routes.
/// Routes are `"METHOD /path"` with the `/api/v1` prefix stripped; the
/// longest matching route wins, so a test can override one endpoint.
class FakeAiAdsBackend {
  final Map<String, FakeHandler> routes = {};
  final List<SentRequest> sent = [];

  FakeAiAdsBackend() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'creator-1',
    });
    ApiClient.httpClient = MockClient((request) async {
      final path = _stripPrefix(request.url.path);
      final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, dynamic>;
      final req = SentRequest(request.method, path, request.url.queryParameters, body);
      sent.add(req);
      final handler = routes['${request.method} $path'];
      if (handler == null) return error(404, 'No fake for ${request.method} $path');
      return handler(req);
    });
  }

  static String _stripPrefix(String p) {
    final i = p.indexOf('/api/v1/');
    return i >= 0 ? p.substring(i + '/api/v1'.length) : p;
  }

  void on(String route, dynamic data, {int status = 200}) =>
      routes[route] = (_) => ok(data, status: status);

  void fail(String route, int status, String message) => routes[route] = (_) => error(status, message);

  List<SentRequest> calls(String method, String path) =>
      sent.where((r) => r.method == method && r.path == path).toList();

  // UTF-8 like Express sends (backend messages use em dashes).
  static http.Response _json(Map<String, dynamic> body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static http.Response ok(dynamic data, {int status = 200}) => _json({'status': 'success', 'data': data}, status);

  static http.Response error(int status, String message) => _json({'status': 'fail', 'message': message}, status);

  static void reset() => ApiClient.httpClient = http.Client();
}

/// Pumps [screen] on a tall surface (so whole ListViews build) and lets the
/// initial requests settle.
Future<void> pumpAiScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await settle(tester);
}

/// Lets requests, debounced quotes (≤600 ms) and the follow-up frames finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

// ─── Fixtures (shapes match the backend DTOs) ─────────────────────────────────

const campaignId = 'c1';
const base = '/creator/ai-campaigns/$campaignId';

Map<String, dynamic> campaignJson({String? myStatus = 'ACTIVE', String? finalGenerationId, int creditsLeft = 100}) => {
  '_id': campaignId,
  'title': 'Summer Fizz',
  'status': 'LIVE',
  'participationMode': 'OPEN',
  'deadline': '2026-12-01T00:00:00.000Z',
  'seatsLeft': 4,
  'creditsPerCreator': 100,
  'brief': {
    'product': 'Fizz Cola',
    'objective': 'Launch the lime flavour',
    'keyMessage': 'Zero sugar, all zing',
    'callToAction': 'Grab one today',
    'dos': ['Show the can'],
    'donts': ['No competitors'],
    'forbiddenClaims': ['cures thirst forever'],
  },
  'format': {'aspectRatio': '9:16', 'minDurationSeconds': 10, 'maxDurationSeconds': 20, 'language': 'English'},
  'assets': [
    {'_id': 'a1', 'role': 'LOGO', 'kind': 'image', 'handle': 'img1', 'mandatory': true, 'viewUrl': 'https://s3/logo.png'},
    {'_id': 'a2', 'role': 'JINGLE', 'kind': 'audio', 'label': 'Fizz jingle', 'viewUrl': 'https://s3/j.mp3'},
  ],
  if (myStatus != null)
    'myParticipation': {
      '_id': 'p1',
      'status': myStatus,
      'creditsLeft': creditsLeft,
      'allocatedCredits': 100,
      'finalGenerationId': finalGenerationId,
    },
};

Map<String, dynamic> generationJson({
  required String id,
  String stage = 'SCRIPT',
  String status = 'COMPLETED',
  int version = 1,
  String operation = 'GENERATE',
  Map<String, dynamic>? output,
  String? scriptId,
  String instructions = '',
}) => {
  '_id': id,
  'stage': stage,
  'operation': operation,
  'versionNumber': version,
  'status': status,
  'instructions': instructions,
  'scriptId': scriptId,
  'quotedCredits': 5,
  'chargedCredits': status == 'COMPLETED' ? 4 : 0,
  'chargeState': status == 'COMPLETED' ? 'SETTLED' : 'HELD',
  'createdAt': '2026-10-01T10:00:00.000Z',
  'output': output ??
      switch (stage) {
        'SCRIPT' => {'text': 'Scene 1: a can pops open.', 'script': {'scenes': [{'durationSeconds': 5, 'visual': 'Can pops'}]}},
        'IMAGE' => {'imageUrls': ['https://s3/i0.png', 'https://s3/i1.png']},
        _ => status == 'COMPLETED' ? {'videoUrl': 'https://s3/v.mp4'} : <String, dynamic>{},
      },
};

Map<String, dynamic> workspaceJson({List<Map<String, dynamic>> generations = const [], int creditsLeft = 100, int reserve = 3}) => {
  'campaign': {'status': 'LIVE', 'deadline': '2026-12-01T00:00:00.000Z', 'format': {'minDurationSeconds': 10, 'maxDurationSeconds': 20}},
  'creditsLeft': creditsLeft,
  'allocatedCredits': 100,
  'prices': {
    'scriptUpTo': 2,
    'imageEach': 3,
    'videoPerSecond': {'480p': 1.5, '720p': 2.5, '1080p': null},
    'reservedForEvaluation': reserve,
  },
  'generations': generations,
};

Map<String, dynamic> quoteJson(int credits, {int creditsLeft = 100, bool canAfford = true, int reserve = 3}) => {
  'credits': credits,
  'creditsLeft': creditsLeft,
  'reservedForEvaluation': reserve,
  'canAfford': canAfford,
  'breakdown': {'note': 'est.'},
};

Map<String, dynamic> evaluationJson({String id = 'e1', String videoId = 'v1', String status = 'COMPLETED', int? score = 72}) => {
  '_id': id,
  'videoGenerationId': videoId,
  'status': status,
  'overallScore': status == 'COMPLETED' ? score : null,
  'criteria': [
    {'name': 'Brief fit', 'weight': 30, 'score': 8, 'reason': 'On message'},
    {'name': 'Brand assets', 'weight': 25, 'score': 6.5, 'reason': 'Logo late'},
  ],
  'mandatoryAssets': [{'handle': 'img1', 'present': false, 'note': 'Never shown'}],
  'mandatoryPass': false,
  'forbiddenClaimViolations': <String>[],
  'safetyIssues': <String>[],
  'feedback': [{'atSeconds': 3.5, 'note': 'Logo too small'}],
  'suggestions': ['Show the logo in the first 2 seconds'],
  'summary': 'Solid ad, logo missing.',
  'quotedCredits': 3,
  'chargedCredits': 3,
  'createdAt': '2026-10-01T11:00:00.000Z',
};
