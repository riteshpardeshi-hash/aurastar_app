import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/category_store.dart';

// Categories used to be fetched separately by five screens, with no saved copy: every
// screen paid a round trip and a dropped connection left the create screen with
// "ClientConnection closed before full header was received". The store keeps one saved
// copy on the device and refreshes it in the background.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = CategoryStore.instance;
  late List<Uri> requests;

  http.Response page(List<Map<String, dynamic>> categories, {String? nextCursor}) => http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'categories': categories,
            'pagination': {'hasNextPage': nextCursor != null, if (nextCursor != null) 'nextCursor': nextCursor},
          },
        }),
        200,
      );

  final fitness = {'_id': 'c1', 'name': 'Fitness', 'thumbnailUrl': 'https://s3/presigned?X-Amz-Expires=900'};
  final dance = {'_id': 'c2', 'name': 'Dance'};

  void serve(Future<http.Response> Function(http.Request) handler) {
    ApiClient.httpClient = MockClient((req) {
      requests.add(req.url);
      return handler(req);
    });
  }

  setUp(() {
    requests = [];
    store.resetForTest();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  test('the first load fetches; later loads come from memory without a request', () async {
    serve((_) async => page([fitness, dance]));
    expect((await store.load()).map((c) => c['name']), ['Fitness', 'Dance']);
    await store.load();
    await store.load();
    expect(requests, hasLength(1));
  });

  test('after an app restart the saved list is used with no request', () async {
    serve((_) async => page([fitness]));
    await store.load();
    store.resetForTest(); // memory gone, like a cold start
    serve((_) async => throw http.ClientException('offline'));
    requests.clear();

    final list = await store.load();
    expect(list.single['name'], 'Fitness');
    expect(requests, isEmpty, reason: 'a fresh saved copy needs no network');
  });

  test('a stale saved list is returned at once and refreshed in the background', () async {
    SharedPreferences.setMockInitialValues({
      'category_store_v1': jsonEncode({
        'savedAt': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'categories': [
          {'_id': 'old', 'name': 'Old Category'},
        ],
      }),
    });
    final refresh = Completer<http.Response>();
    serve((_) => refresh.future);

    final first = await store.load();
    expect(first.single['name'], 'Old Category', reason: 'no waiting on the network');
    await Future<void>.delayed(const Duration(milliseconds: 20)); // the refresh is fired, not awaited
    expect(requests, hasLength(1), reason: 'a background refresh started');

    refresh.complete(page([dance]));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect((await store.load()).single['name'], 'Dance');
  });

  test('offline with a saved copy still works; offline with nothing saved throws a readable error', () async {
    serve((_) async => throw http.ClientException('Connection closed before full header was received'));
    await expectLater(store.load(), throwsA(isA<CategoryLoadException>()));
    expect(requests, hasLength(2), reason: 'one quiet retry before giving up');
    expect(const CategoryLoadException().toString(), "We couldn't load the categories.");

    serve((_) async => page([fitness]));
    await store.load(); // now saved
    store.resetForTest();
    serve((_) async => throw http.ClientException('offline'));
    expect((await store.load()).single['name'], 'Fitness');
  });

  test('a dropped connection is retried once and then succeeds', () async {
    var calls = 0;
    serve((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('Connection reset by peer');
      return page([fitness]);
    });
    expect((await store.load()).single['name'], 'Fitness');
    expect(calls, 2);
  });

  test('screens loading at the same time share one request', () async {
    final response = Completer<http.Response>();
    serve((_) => response.future);
    final a = store.load();
    final b = store.load();
    final c = store.load();
    response.complete(page([fitness]));
    await Future.wait([a, b, c]);
    expect(requests, hasLength(1));
  });

  test('every page is fetched (the API returns 20 per page by default)', () async {
    serve((req) async {
      final cursor = req.url.queryParameters['cursor'];
      expect(req.url.queryParameters['limit'], '100');
      return cursor == null ? page([fitness], nextCursor: 'next-1') : page([dance]);
    });
    expect((await store.load()).map((c) => c['_id']), ['c1', 'c2']);
    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['cursor'], 'next-1');
  });

  test('only id and name are saved — never the expiring presigned thumbnail URL', () async {
    serve((_) async => page([fitness]));
    final list = await store.load();
    expect(list.single.keys, unorderedEquals(['_id', 'name']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('category_store_v1'), isNot(contains('X-Amz')));
  });

  test('entries without an id or a name are skipped', () async {
    serve((_) async => page([
          fitness,
          {'_id': '', 'name': 'No id'},
          {'_id': 'c3', 'name': '   '},
        ]));
    expect((await store.load()).map((c) => c['_id']), ['c1']);
  });

  test('invalidate forces the next load to fetch (a category was retired)', () async {
    serve((_) async => page([fitness, dance]));
    await store.load();
    await store.invalidate();
    serve((_) async => page([dance]));
    expect((await store.load()).single['name'], 'Dance');
    expect(store.peek()!.single['name'], 'Dance');
  });

  test('a corrupt saved entry is ignored and refetched', () async {
    SharedPreferences.setMockInitialValues({'category_store_v1': 'not json'});
    serve((_) async => page([fitness]));
    expect((await store.load()).single['name'], 'Fitness');
    expect(requests, hasLength(1));
  });

  test('a backend error response is not saved as an empty list', () async {
    serve((_) async => http.Response(jsonEncode({'status': 'error', 'message': 'boom'}), 500));
    await expectLater(store.load(), throwsA(isA<CategoryLoadException>()));
    expect(store.peek(), isNull);
  });

  test('nameById maps ids to names for thumbnails', () async {
    serve((_) async => page([fitness, dance]));
    expect(await store.nameById(), {'c1': 'Fitness', 'c2': 'Dance'});
  });
}
