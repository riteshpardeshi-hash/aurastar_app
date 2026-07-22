import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/video_cache_service.dart';

// Regression coverage for the "ghost unavailable" bug: once a challenge's
// reference video finishes backend processing, Challenge.videoUrl switches
// from a direct S3 file to a public HLS master playlist (.m3u8) — see
// Challenge.videoUrl in openapi.yaml. A plain GET on that URL only fetches
// the small text manifest, not playable video bytes; the old code cached
// that text as if it were a downloaded .mp4, so CameraScreen's ghost
// overlay permanently failed to initialize for every processed challenge.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('video_cache_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    VideoCacheService.httpClient = http.Client();
    tempDir.deleteSync(recursive: true);
  });

  test('ensureCached never hits the network for an HLS (.m3u8) URL', () async {
    var requestCount = 0;
    VideoCacheService.httpClient = MockClient((request) async {
      requestCount++;
      return http.Response('#EXTM3U\n#EXT-X-VERSION:3\n', 200);
    });

    final path = await VideoCacheService.ensureCached(
      'https://processed-bucket.s3.amazonaws.com/processed/uid/uuid/hls/hls.m3u8',
    );

    expect(path, isNull);
    expect(requestCount, 0);
  });

  test('ensureCached still downloads and caches a plain .mp4 reference video',
      () async {
    var requestCount = 0;
    VideoCacheService.httpClient = MockClient((request) async {
      requestCount++;
      return http.Response.bytes([1, 2, 3, 4], 200);
    });

    final path = await VideoCacheService.ensureCached(
      'https://bucket.s3.amazonaws.com/raw/uid/uuid/original.mp4',
    );

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
    expect(requestCount, 1);
  });
}
