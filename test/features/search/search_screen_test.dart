import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/explore/screens/brand_profile_screen.dart';
import 'package:aura_app/features/search/search_screen.dart';

// Regression coverage: SearchScreen used to hard-cap at whatever the
// backend's default page returns (10 items) and never sent `page`, even
// though GET /search paginates single-type searches up to 100 items/page
// (`type=all` never paginates, but a specific type like `creators` does,
// via the backend's `paginatedResponse` envelope: items under
// `data.responses`, with top-level `page` / `totalPages`). Scrolling to the
// bottom of a single-type result list now fetches and appends the next
// page instead of silently stopping at 10.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  Map<String, dynamic> creator(String id) => {
        '_id': id,
        'displayName': 'Creator $id',
        'username': id,
        'avatar': '',
      };

  testWidgets('scrolling to the bottom of a single-type search fetches page 2',
      (tester) async {
    final requestedPages = <int>[];

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/search')) {
        final page = int.parse(request.url.queryParameters['page']!);
        requestedPages.add(page);
        final docs = page == 1
            ? List.generate(20, (i) => creator('p1-$i'))
            : List.generate(20, (i) => creator('p2-$i'));
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'responses': docs,
              'page': page, 'totalPages': 2, 'totalCount': 40, 'limit': 20,
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/search/recent')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'items': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();

    // Switch to a single-type filter — pagination only applies there.
    await tester.tap(find.text('Creators'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 500)); // clear debounce
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(requestedPages, [1],
        reason: 'first search must request page 1');
    expect(find.text('Creator p1-0'), findsOneWidget);

    // Scroll to the bottom of the results list.
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(requestedPages, [1, 2],
        reason: 'reaching the bottom must fetch page 2, not stop at 10 results');

    // The list grew taller once page 2 was appended — scroll again so the
    // newly-appended tail item is within the lazily-built viewport.
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pump();

    expect(find.text('Creator p2-19'), findsOneWidget,
        reason: 'page 2 results must be appended, not replace page 1');
  });

  testWidgets(
      "an older query's slow response must not overwrite a newer query's "
      'results', (tester) async {
    // The first ("slow") query's response is held back until after the
    // second ("fast") query's has already landed, mirroring real network
    // jitter where responses can resolve out of order.
    final slowResponseGate = Completer<void>();

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/search')) {
        final q = request.url.queryParameters['q'];
        if (q == 'slow') {
          await slowResponseGate.future;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'responses': [creator('stale-result')],
                'page': 1, 'totalPages': 1, 'totalCount': 1, 'limit': 20,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'responses': [creator('fresh-result')],
              'page': 1, 'totalPages': 1, 'totalCount': 1, 'limit': 20,
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/search/recent')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'items': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.tap(find.text('Creators'));
    await tester.pump();

    // Fire the slow query first, letting its debounce elapse so the request
    // actually dispatches (and hangs on slowResponseGate).
    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump(const Duration(milliseconds: 500));

    // Now fire a second, faster query before the first has resolved.
    await tester.enterText(find.byType(TextField), 'fresh');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Creator fresh-result'), findsOneWidget,
        reason: 'the newer query\'s results must be showing');

    // Let the stale first response land after the fact.
    slowResponseGate.complete();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Creator fresh-result'), findsOneWidget,
        reason: 'the newer results must still be showing');
    expect(find.text('Creator stale-result'), findsNothing,
        reason: "the older, slower query's response must not overwrite the "
            "newer query's results once it finally resolves");
  });

  testWidgets('the Brands filter lists brands from a type=brands search',
      (tester) async {
    final requestedTypes = <String?>[];
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/search')) {
        requestedTypes.add(request.url.queryParameters['type']);
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'responses': [
                {'_id': 'brand-1', 'displayName': 'Nova Brand', 'profileName': 'nova', 'role': 'brand'},
              ],
              'page': 1, 'totalPages': 1, 'totalCount': 1, 'limit': 20,
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/search/recent')) {
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'items': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.tap(find.text('Brands'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'nova');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(requestedTypes, contains('brands'));
    expect(find.text('Nova Brand'), findsOneWidget,
        reason: 'brands under data.responses must be listed');
    expect(find.text('Brand · @nova'), findsOneWidget,
        reason: 'the handle falls back to profileName');
  });

  testWidgets('tapping a Brand search result opens its brand profile',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenges': [],
              'brands': [
                {'_id': 'brand-1', 'displayName': 'Nova Brand', 'username': 'nova'},
              ],
              'creators': [],
              'categories': [],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/search/recent')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'items': []}}), 200);
      }
      if (path.endsWith('/brands/brand-1')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'_id': 'brand-1', 'displayName': 'Nova Brand', 'avatar': ''},
          }),
          200,
        );
      }
      if (path.endsWith('/challenges') || path.endsWith('/followers')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'nova');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Nova Brand'), findsOneWidget);
    await tester.tap(find.text('Nova Brand'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(BrandProfileScreen), findsOneWidget,
        reason: 'a Brand search result must open BrandProfileScreen (backed '
            'by GET /brands/{id}), not CreatorProfileScreen (GET '
            '/creators/{id} is the wrong collection for a Brand entity)');
  });
}
