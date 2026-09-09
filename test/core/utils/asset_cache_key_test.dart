import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/asset_cache_key.dart';

// Regression coverage for "thumbnails load very slowly on every screen".
// Backend `thumbnailUrl` / `videoUrl` are presigned S3 URLs re-signed on
// every read, so the same object arrives as a different string each time and
// every URL-keyed cache (Image.network's, VideoCacheService's) misses on
// every refresh. assetCacheKey collapses all signed variants of one object
// to a single key.
void main() {
  test('two presigned variants of the same object share one key', () {
    const a =
        'https://bucket.s3.amazonaws.com/challenge-thumbnails/uid/abc.jpg'
        '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20260907T090000Z'
        '&X-Amz-Expires=3600&X-Amz-Signature=aaaa&x-id=GetObject';
    const b =
        'https://bucket.s3.amazonaws.com/challenge-thumbnails/uid/abc.jpg'
        '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20260908T120000Z'
        '&X-Amz-Expires=3600&X-Amz-Signature=zzzz&x-id=GetObject';

    expect(assetCacheKey(a), assetCacheKey(b));
    expect(assetCacheKey(a),
        'https://bucket.s3.amazonaws.com/challenge-thumbnails/uid/abc.jpg');
  });

  test('different objects keep different keys', () {
    expect(
      assetCacheKey('https://b.s3.amazonaws.com/x/one.jpg?X-Amz-Signature=q'),
      isNot(assetCacheKey(
          'https://b.s3.amazonaws.com/x/two.jpg?X-Amz-Signature=q')),
    );
  });

  test('a URL with no query is returned as its own key', () {
    expect(assetCacheKey('https://example.com/v/clip.mp4'),
        'https://example.com/v/clip.mp4');
  });

  test('host/scheme are preserved; a different host is a different key', () {
    expect(
      assetCacheKey('https://a.example.com/x.jpg?s=1'),
      isNot(assetCacheKey('https://b.example.com/x.jpg?s=1')),
    );
  });

  test('non-URL / empty / relative inputs pass straight through', () {
    expect(assetCacheKey(''), '');
    expect(assetCacheKey('not a url'), 'not a url');
    expect(assetCacheKey('/local/path.jpg'), '/local/path.jpg');
  });
}
