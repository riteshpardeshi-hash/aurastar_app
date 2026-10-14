import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creator_page_service.dart';

// Regression coverage for the Dashboard's "Become a Creator" button/banner
// being invisible for every player: fetchOwnPage() used to return
// `res['data']` as-is. The live GET /creator/page response wraps the
// profile as `data: {profile: null}` for a user with no creator page
// (rather than `data: null`, despite the documented schema), so the old
// code returned a non-null `{profile: null}` map. Dashboard's
// `hasCreatorPage = results[2] != null` then evaluated true for every
// player, hiding the become-creator section entirely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  test('fetchOwnPage returns null when the caller has no creator page yet',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'profile': null},
        }),
        200,
      );
    });

    expect(await CreatorPageService().fetchOwnPage(), isNull);
  });

  test('fetchOwnPage unwraps the profile map when the caller has a page',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'profile': {'username': 'johndoe', 'status': 'ACTIVE'},
          },
        }),
        200,
      );
    });

    final result = await CreatorPageService().fetchOwnPage();

    expect(result?['username'], 'johndoe');
    expect(result?['status'], 'ACTIVE');
  });

  test('fetchOwnPage falls back to the flat data map if it is not profile-wrapped',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'username': 'janedoe', 'status': 'ACTIVE'},
        }),
        200,
      );
    });

    final result = await CreatorPageService().fetchOwnPage();

    expect(result?['username'], 'janedoe');
  });

  test('fetchOwnPage returns null on a non-success status', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 401);
    });

    expect(await CreatorPageService().fetchOwnPage(), isNull);
  });

  // Regression: isCreatorCached() cached its first answer — including `false`
  // from before the user became a creator — for the whole session, so a creator
  // kept seeing the "Become a Creator" banner.
  group('isCreatorCached', () {
    setUp(CreatorPageService.invalidateCreatorCache);

    http.Response ok(Object data) =>
        http.Response(jsonEncode({'status': 'success', 'data': data}), 200);

    test('a false answer is not cached once the user becomes a creator',
        () async {
      var role = 'user';
      var hasPage = false;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/profile')) {
          return ok({'user': {'role': role}});
        }
        return ok({'profile': hasPage ? {'username': 'neha'} : null});
      });

      expect(await CreatorPageService().isCreatorCached(), isFalse);
      role = 'creator';
      expect(await CreatorPageService().isCreatorCached(), isTrue);
    });

    test('an existing creator page counts even if the role lags', () async {
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/profile')) {
          return ok({'user': {'role': 'user'}});
        }
        return ok({'profile': {'username': 'neha'}});
      });

      expect(await CreatorPageService().isCreatorCached(), isTrue);
    });
  });
}
