import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/globals.dart' as globals;
import 'package:aura_app/features/challenges/screens/camera_screen.dart';

// Regression coverage for a "ghost mode isn't actually muted" complaint.
// CameraScreen's ghost overlay (a PiP of the challenge's reference video)
// is muted once in _initGhost() via setVolume(0.0), before it's ever
// played. That mute doesn't reliably survive to the moment playback
// actually starts: _startRecording() immediately follows
// `CameraController.startVideoRecording()`, which activates the device's
// audio-recording session (enableAudio: true) — a system-level audio
// route change that can silently reset a player's volume on both
// ExoPlayer and AVPlayer. The fix re-asserts setVolume(0.0) right before
// the ghost controller's play() call, not just once back at init.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCameraPlatform fakeCamera;
  late _FakeVideoPlayerPlatform fakeVideoPlayer;

  setUp(() {
    fakeCamera = _FakeCameraPlatform();
    CameraPlatform.instance = fakeCamera;
    fakeVideoPlayer = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakeVideoPlayer;
    PermissionHandlerPlatform.instance = _FakeGrantedPermissionHandler();
    globals.cameras = const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  });

  testWidgets(
      'starting a recording re-mutes the ghost overlay right before it plays',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        // .m3u8 short-circuits VideoCacheService.ensureCached() to null
        // (HLS manifests can't be cached as a flat file — see
        // video_cache_service_test.dart), so the ghost controller streams
        // straight from this URL via the faked platform, no disk/network
        // I/O involved.
        referenceVideoUrl: 'https://example.com/reference.m3u8',
      ),
    ));

    // Let _initCamera and _initGhost (both async) settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('recordButton')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final log = fakeVideoPlayer.callLog;
    final playIndex = log.indexOf('play');
    expect(playIndex, greaterThan(-1),
        reason: 'recording should have started ghost playback');

    final muteCallsBeforePlay =
        log.take(playIndex).where((c) => c == 'setVolume(0.0)').length;
    expect(muteCallsBeforePlay, greaterThanOrEqualTo(2),
        reason:
            'volume must be re-asserted to 0 immediately before play(), not '
            'just once back at init — otherwise the audio-session change '
            'from starting camera recording can leave the ghost overlay '
            'audible');
    expect(log[playIndex - 1], 'setVolume(0.0)',
        reason: 'the mute re-assertion must be the call immediately '
            'preceding play(), so nothing can slip in between them');
  });

  // Regression coverage for "the reference video stops rendering frames and
  // freezes": the ghost controller was built without mixWithOthers, so it
  // requested *exclusive* audio focus. _startRecording() immediately calls
  // CameraController.startVideoRecording (enableAudio: true), activating
  // the mic's own audio session — exactly the kind of focus-taking event
  // that silently auto-pauses an exclusive-focus player with no signal to
  // ever resume it, which is what made the ghost overlay freeze right after
  // recording started.
  testWidgets(
      'the ghost overlay controller requests mixWithOthers, so starting the '
      'recording\'s own audio session cannot silently pause it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        referenceVideoUrl: 'https://example.com/reference.m3u8',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fakeVideoPlayer.mixWithOthersCalls, contains(true),
        reason: 'without mixWithOthers, starting the camera\'s own audio '
            'session for recording can steal exclusive audio focus from '
            'the ghost player and pause it with no way to auto-resume');
  });

  // Regression coverage: the ghost overlay's reference clip streams over the
  // network (HLS can't be pre-cached locally — see VideoCacheService), so a
  // slow connection can stall mid-playback. VideoPlayer itself gives no
  // visual cue of that — it just silently holds the last decoded frame,
  // which reads as "frozen/broken" rather than "buffering, will resume."
  testWidgets(
      'shows a buffering indicator over the ghost overlay while its stream stalls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        referenceVideoUrl: 'https://example.com/reference.m3u8',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Only one CircularProgressIndicator at this point: the "ghost not
    // ready yet" spinner should already be gone once initialization settled.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    fakeVideoPlayer.setBuffering(true);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'a mid-playback stall must show a buffering indicator, not '
            'silently hold the last frame with no explanation');

    fakeVideoPlayer.setBuffering(false);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the indicator must disappear again once buffering ends');
  });

  // Regression coverage: _initCamera used to fire the old CameraController's
  // dispose() without awaiting it before constructing/initializing the new
  // one for the flipped lens. dispose() is an async native call that frees
  // the hardware camera session; not awaiting it let the old session's
  // teardown overlap with the new session's acquisition. Most camera HALs
  // (Android's camera2 in particular) only allow one open session at a
  // time, so that race either threw or hung indefinitely — this is what
  // made flipping the camera get stuck on the loading spinner. The fake
  // platform below models the race: createCamera() throws if a previous
  // dispose() is still in flight, which the pre-fix code triggers because
  // it never waits for that dispose to finish.
  testWidgets(
      'flipping the camera awaits the previous session\'s disposal before '
      'opening the new one', (tester) async {
    globals.cameras = const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      ),
    ];

    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byIcon(Icons.flip_camera_ios_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flip_camera_ios_rounded));
    // Let the (deliberately slow) disposal of the old session and the new
    // controller's initialize both settle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Camera unavailable'), findsNothing,
        reason: 'flipping cameras must not race the previous session\'s '
            'disposal against the new controller\'s initialize()');
    expect(find.byIcon(Icons.flip_camera_ios_rounded), findsOneWidget,
        reason: 'camera should be back in the ready state after flipping, '
            'not stuck on the loading spinner');
  });

  // Regression coverage: neither this screen nor the app manifest restricts
  // device rotation (checked live: no android:screenOrientation on the
  // activity, and Info.plist lists landscape as a supported orientation),
  // and _initCamera never called CameraController.lockCaptureOrientation().
  // So a device that was rotated during recording captured video
  // tagged/encoded in that orientation — the sensor and encoder have no
  // idea this UI is portrait-only. That's what produced a submission that
  // played back sideways (and got flagged by the AI scorer itself for
  // "wrong orientation", since it saw the same file).
  testWidgets('camera initialization locks capture orientation to portrait',
      (tester) async {
    globals.cameras = const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];

    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fakeCamera.lockedOrientations, [DeviceOrientation.portraitUp],
        reason: 'recording must always be locked to portraitUp regardless '
            'of how the device happens to be held/rotated, otherwise the '
            'captured video is encoded sideways');
  });

  // Coverage for the self-timer: selecting a delay must count down on
  // screen and only start the actual recording once it reaches zero — not
  // start immediately like a normal tap.
  testWidgets(
      'tapping record with a timer delay selected counts down before '
      'recording actually starts', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Timer Off'), findsOneWidget);
    await tester.tap(find.text('Timer Off'));
    await tester.pump();
    expect(find.text('Timer 5s'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();

    expect(fakeCamera.startVideoCapturingCalls, 0,
        reason: 'recording must not start the instant a timer delay is '
            'selected and tapped — it should count down first');
    expect(find.text('5'), findsOneWidget,
        reason: 'the countdown overlay should show the selected delay');

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(fakeCamera.startVideoCapturingCalls, 1,
        reason: 'recording should start automatically once the countdown '
            'reaches zero');
  });

  testWidgets(
      'tapping record again during the countdown cancels it instead of '
      'starting recording', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Timer Off'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();

    expect(find.text('Timer 5s'), findsOneWidget,
        reason: 'cancelling the countdown returns to the idle state with '
            'the chosen delay still selected');

    // Let time pass to make sure a cancelled countdown never fires late.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(fakeCamera.startVideoCapturingCalls, 0,
        reason: 'a cancelled countdown must never start recording');
  });

  // Coverage for the post-ghost auto-stop: once the reference ("ghost") clip
  // has played through once, the take is allowed to run at most 10 more
  // seconds and then stops itself, so a submission can't run arbitrarily
  // longer than the reference it's being scored against. The fake video
  // player reports the ghost clip as 5s long (see
  // _FakeVideoPlayerPlatform.videoEventsFor), so the recording must stop at
  // 5s + 10s = 15s elapsed, and not before.
  testWidgets(
      'recording auto-stops 10s after the ghost reference clip ends',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        referenceVideoUrl: 'https://example.com/reference.m3u8',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    expect(fakeCamera.startVideoCapturingCalls, 1);
    expect(fakeCamera.stopVideoRecordingCalls, 0);

    // Pump to 14s elapsed — one second short of the 5s + 10s deadline.
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(fakeCamera.stopVideoRecordingCalls, 0,
        reason: 'must not stop until the full 10s grace after the ghost ends');
    expect(find.textContaining('Auto-stop in'), findsOneWidget,
        reason: 'the grace countdown should be visible once the ghost ended');

    // Cross the 15s mark.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fakeCamera.stopVideoRecordingCalls, 1,
        reason: 'recording auto-stops once the 10s post-ghost grace elapses');
  });

  // Regression coverage: when camera/mic permission is permanently denied,
  // CameraScreen showed a dead-end "Camera access needed" screen with no
  // back button anywhere on it (unlike the ready-camera view, which has its
  // own top-bar back arrow) — the only way out was killing the app. The fix
  // overlays a back button on the error/loading states too.
  testWidgets(
      'the permission-denied error screen has a working back button',
      (tester) async {
    PermissionHandlerPlatform.instance =
        _FakePermanentlyDeniedPermissionHandler();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CameraScreen(
                    challengeTitle: 'Test Challenge',
                    challengeId: 'challenge-1',
                  ),
                ),
              ),
              child: const Text('Open camera'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Camera access needed'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget,
        reason: 'the permission-denied screen must offer a way back — '
            'previously there was none, trapping the user');

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Camera access needed'), findsNothing,
        reason: 'tapping back must actually pop the camera screen');
    expect(find.text('Open camera'), findsOneWidget,
        reason: 'should have returned to the screen that opened the camera');
  });

  testWidgets('the "Open Settings" button text is readable against its background',
      (tester) async {
    PermissionHandlerPlatform.instance =
        _FakePermanentlyDeniedPermissionHandler();

    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Open Settings'));
    final resolvedColor =
        button.style?.foregroundColor?.resolve(<WidgetState>{});

    expect(resolvedColor, Colors.white,
        reason: 'the previous style left foregroundColor unset, so the '
            'button text fell back to a near-invisible dark color on the '
            'purple background');
  });

  testWidgets(
      'recording never auto-stops when the challenge has no ghost reference',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CameraScreen(
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        // No referenceVideoUrl → no ghost clip → nothing to measure a grace
        // window from, so the user is in full manual control of stopping.
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    expect(fakeCamera.startVideoCapturingCalls, 1);

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(fakeCamera.stopVideoRecordingCalls, 0,
        reason: 'with no ghost reference there is no auto-stop deadline');
    expect(find.textContaining('Auto-stop in'), findsNothing);
  });
}

class _FakeGrantedPermissionHandler extends PermissionHandlerPlatform {
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
      List<Permission> permissions) async {
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

class _FakePermanentlyDeniedPermissionHandler extends PermissionHandlerPlatform {
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
      List<Permission> permissions) async {
    return {
      for (final p in permissions) p: PermissionStatus.permanentlyDenied
    };
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return PermissionStatus.permanentlyDenied;
  }
}

class _FakeCameraPlatform extends CameraPlatform {
  int _nextCameraId = 0;
  // Models a camera HAL that only allows one open session at a time (true
  // of Android's camera2 API): tracks camera ids that have been created but
  // not yet handed to dispose(). CameraController.dispose() itself awaits
  // `_initializeFuture` before ever calling this platform's dispose() — so
  // even though that await resolves near-instantly (the future is already
  // completed by the time a flip happens), it still yields at least one
  // microtask. A caller that fires dispose() without awaiting it therefore
  // reaches a new createCamera() call in the very same synchronous turn,
  // strictly before the old session's dispose() has even been invoked here
  // — this set catches exactly that overlap, the same overlap that hangs
  // or throws against a real camera HAL.
  final Set<int> _openIds = {};
  final List<DeviceOrientation> lockedOrientations = [];
  int startVideoCapturingCalls = 0;
  int stopVideoRecordingCalls = 0;

  @override
  Future<void> lockCaptureOrientation(
      int cameraId, DeviceOrientation orientation) async {
    lockedOrientations.add(orientation);
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    if (_openIds.isNotEmpty) {
      throw CameraException('CameraAccessException',
          'Camera is still open on a previous, not-yet-released session');
    }
    final id = _nextCameraId++;
    _openIds.add(id);
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    return Stream.value(CameraInitializedEvent(
      cameraId,
      1920,
      1080,
      ExposureMode.auto,
      false,
      FocusMode.auto,
      false,
    ));
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  // CameraController.initialize() does `onCameraError(id).first` (unawaited,
  // just to react to a later error if one ever arrives) — a Stream.empty()
  // closes immediately without emitting, so `.first` throws "Bad state: No
  // element" and fails the test even though nothing actually went wrong.
  // A broadcast controller that's simply never closed keeps that `.first`
  // future pending forever, same as a real error stream that hasn't fired.
  final StreamController<CameraErrorEvent> _cameraErrorController =
      StreamController<CameraErrorEvent>.broadcast();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _cameraErrorController.stream;

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    startVideoCapturingCalls++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopVideoRecordingCalls++;
    return XFile('${Directory.systemTemp.path}/fake_recording.mp4');
  }

  @override
  Future<void> dispose(int cameraId) async {
    _openIds.remove(cameraId);
  }
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  final List<String> callLog = [];
  final List<bool> mixWithOthersCalls = [];
  // Kept open (unlike the old Stream.value, which closed after one event)
  // so a test can push further events — e.g. bufferingStart/bufferingEnd —
  // at will after initialization. The "initialized" event added in
  // createWithOptions is queued by the controller until videoEventsFor's
  // caller subscribes, same as a real platform's event channel.
  final Map<int, StreamController<VideoEvent>> _eventControllers = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    final controller = StreamController<VideoEvent>();
    _eventControllers[id] = controller;
    controller.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1080, 1920),
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return _eventControllers[playerId]!.stream;
  }

  /// Simulates the reference clip's network stream stalling (or resuming) —
  /// pushes a bufferingStart/bufferingEnd event for the most recently
  /// created player, which is always the ghost overlay's controller in
  /// these tests (the only VideoPlayerController CameraScreen ever builds).
  void setBuffering(bool buffering) {
    final id = _nextPlayerId - 1;
    _eventControllers[id]?.add(VideoEvent(
      eventType:
          buffering ? VideoEventType.bufferingStart : VideoEventType.bufferingEnd,
    ));
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    mixWithOthersCalls.add(mixWithOthers);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    callLog.add('setLooping');
  }

  @override
  Future<void> play(int playerId) async {
    callLog.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    callLog.add('pause');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    callLog.add('setVolume($volume)');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}
