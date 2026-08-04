import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
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
}

class _FakeGrantedPermissionHandler extends PermissionHandlerPlatform {
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
      List<Permission> permissions) async {
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

class _FakeCameraPlatform extends CameraPlatform {
  int _nextCameraId = 0;

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async =>
      _nextCameraId++;

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

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async =>
      XFile('${Directory.systemTemp.path}/fake_recording.mp4');

  @override
  Future<void> dispose(int cameraId) async {}
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  final List<String> callLog = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1080, 1920),
    ));
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
