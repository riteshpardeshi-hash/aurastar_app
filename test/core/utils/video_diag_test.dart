import 'package:aura_app/core/utils/video_diag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report omits the presigned query string but keeps the error', () {
    final report = describeVideoFailure(
      Exception('DecoderInitializationException'),
      where: 'test',
      url: 'https://bucket.s3.amazonaws.com/raw/a.mp4?X-Amz-Signature=secret',
      fromCache: false,
      playerError: 'MediaCodec failed',
    );
    expect(report, contains('https://bucket.s3.amazonaws.com/raw/a.mp4'));
    expect(report, isNot(contains('secret')));
    expect(report, contains('DecoderInitializationException'));
    expect(report, contains('network stream'));
    expect(report, contains('MediaCodec failed'));
  });
}
