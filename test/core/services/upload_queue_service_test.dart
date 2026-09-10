import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/upload_queue_service.dart';

// The pending-upload record carries the `mirrored` flag (ADR 020) so a
// front-camera take whose upload failed re-opens PreviewScreen from the
// dashboard banner with the same orientation it was reviewed in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File videoFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    videoFile = File(
        '${Directory.systemTemp.path}/uq_test_${DateTime.now().microsecondsSinceEpoch}.mp4');
    await videoFile.writeAsBytes(const [0, 1, 2, 3]);
  });

  tearDown(() async {
    if (await videoFile.exists()) await videoFile.delete();
    await UploadQueueService.clear();
  });

  test('mirrored flag round-trips through save/getPending', () async {
    await UploadQueueService.save(
      videoPath: videoFile.path,
      challengeId: 'c1',
      challengeTitle: 'Head Tilt',
      mirrored: true,
    );

    final pending = await UploadQueueService.getPending();
    expect(pending, isNotNull);
    expect(pending!.mirrored, isTrue);
    expect(pending.videoPath, videoFile.path);
  });

  test('mirrored defaults to false when not saved', () async {
    await UploadQueueService.save(
      videoPath: videoFile.path,
      challengeId: 'c1',
      challengeTitle: 'Head Tilt',
    );

    final pending = await UploadQueueService.getPending();
    expect(pending!.mirrored, isFalse);
  });

  test('clear() also drops the mirrored flag', () async {
    await UploadQueueService.save(
      videoPath: videoFile.path,
      challengeId: 'c1',
      challengeTitle: 'Head Tilt',
      mirrored: true,
    );
    await UploadQueueService.clear();

    expect(await UploadQueueService.getPending(), isNull);
    // And a subsequent save without the flag doesn't inherit the old true.
    await UploadQueueService.save(
      videoPath: videoFile.path,
      challengeId: 'c1',
      challengeTitle: 'Head Tilt',
    );
    expect((await UploadQueueService.getPending())!.mirrored, isFalse);
  });
}
