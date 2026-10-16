import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/challenge_create_flow.dart';

// Regression coverage for creating a challenge (2026-10-15): the create request runs a slow AI
// check server-side and can outlive the connection — the server creates the challenge, the app
// sees an error, and a naive retry re-uploaded the video and created a DUPLICATE challenge
// (two identical "talk" drafts in production). ChallengeCreateFlow must make retries safe.
void main() {
  late List<String> calls;
  late int presignCount;
  late Object? Function(String videoId) onCreate; // return non-null to throw it
  late Object? uploadError;

  ChallengeCreateFlow makeFlow() => ChallengeCreateFlow(
        presign: () async {
          presignCount++;
          calls.add('presign');
          return ChallengeVideoUpload(uploadUrl: 'https://s3/u$presignCount', videoId: 'video-$presignCount');
        },
        upload: (url, video, onProgress) async {
          calls.add('upload $url');
          onProgress(1);
          if (uploadError != null) throw uploadError!;
        },
        create: (videoId) async {
          calls.add('create $videoId');
          final err = onCreate(videoId);
          if (err != null) throw err;
        },
      );

  final video = File('/tmp/reference.mp4');

  setUp(() {
    calls = [];
    presignCount = 0;
    onCreate = (_) => null;
    uploadError = null;
  });

  test('happy path: presign → upload → create, reporting each step', () async {
    final steps = <String>[];
    final outcome = await makeFlow().run(video, onStep: steps.add);
    expect(outcome, ChallengeCreateOutcome.created);
    expect(calls, ['presign', 'upload https://s3/u1', 'create video-1']);
    expect(steps, ['request the video upload', 'upload the reference video', 'create the challenge']);
  });

  test('a lost answer then a retry reuses the uploaded video and treats "already claimed" as created', () async {
    final flow = makeFlow();
    // Attempt 1: the server created it, but the app saw a timeout.
    onCreate = (_) => Exception('TimeoutException after 0:03:00.000000');
    await expectLater(flow.run(video), throwsA(isA<Exception>()));
    expect(flow.step, 'create the challenge');
    expect(flow.isUploaded(video), isTrue);

    // Attempt 2: same video → the server says it's already claimed → it was the first attempt.
    onCreate = (_) => 'This video has already been claimed.';
    final outcome = await flow.run(video);

    expect(outcome, ChallengeCreateOutcome.createdEarlier);
    expect(calls, ['presign', 'upload https://s3/u1', 'create video-1', 'create video-1']);
    expect(presignCount, 1, reason: 'no second upload → no duplicate challenge');
  });

  test('"already claimed" on a FIRST create attempt is a real error, not success', () async {
    onCreate = (_) => 'This video has already been claimed.';
    await expectLater(makeFlow().run(video), throwsA('This video has already been claimed.'));
  });

  test('a retry after a genuine create failure that was not created still creates (same video)', () async {
    final flow = makeFlow();
    onCreate = (_) => const SocketException('Connection failed');
    await expectLater(flow.run(video), throwsA(isA<SocketException>()));
    onCreate = (_) => null; // server never got it the first time — now it does
    expect(await flow.run(video), ChallengeCreateOutcome.created);
    expect(calls.where((c) => c.startsWith('upload')), hasLength(1));
  });

  test('a failed upload is retried from the start and reports the upload step', () async {
    final flow = makeFlow();
    uploadError = const SocketException('Connection reset');
    await expectLater(flow.run(video), throwsA(isA<SocketException>()));
    expect(flow.step, 'upload the reference video');
    expect(flow.isUploaded(video), isFalse);

    uploadError = null;
    expect(await flow.run(video), ChallengeCreateOutcome.created);
    expect(calls, ['presign', 'upload https://s3/u1', 'presign', 'upload https://s3/u2', 'create video-2']);
  });

  test('a server validation error on create is passed through and the video is kept for the fix-and-retry', () async {
    final flow = makeFlow();
    onCreate = (_) => 'Category not found.';
    await expectLater(flow.run(video), throwsA('Category not found.'));
    expect(flow.isUploaded(video), isTrue);
  });

  test('picking a different video after a failure uploads the new one', () async {
    final flow = makeFlow();
    onCreate = (_) => Exception('TimeoutException');
    await expectLater(flow.run(video), throwsA(isA<Exception>()));
    flow.reset(); // what the screen does when the user picks another video
    onCreate = (_) => null;
    expect(await flow.run(File('/tmp/other.mp4')), ChallengeCreateOutcome.created);
    expect(presignCount, 2);
  });

  test('after a success the next run starts fresh (new upload, no stale "already claimed" shortcut)', () async {
    final flow = makeFlow();
    await flow.run(video);
    onCreate = (_) => 'This video has already been claimed.';
    await expectLater(flow.run(video), throwsA('This video has already been claimed.'));
    expect(presignCount, 2);
  });
}
