import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../../../core/globals.dart';
import '../../../shared/theme/app_colors.dart';
import 'brand_preview_screen.dart';

class BrandCameraScreen extends StatefulWidget {
  final String       challengeTitle;
  final String       description;
  final String       instructions;
  final String       difficulty;
  final String       categoryId;
  final List<String> instructionSteps;

  const BrandCameraScreen({
    super.key,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
    required this.categoryId,
    this.difficulty       = 'Medium',
    this.instructionSteps = const [],
  });

  @override
  State<BrandCameraScreen> createState() => _BrandCameraScreenState();
}

class _BrandCameraScreenState extends State<BrandCameraScreen>
    with WidgetsBindingObserver {
  CameraController? controller;
  bool recording = false;
  XFile? videoFile;
  int selectedCameraIndex = 0;
  bool _cameraError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initCamera(selectedCameraIndex);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final cam = controller;
      controller = null;
      if (mounted) setState(() => recording = false);
      cam?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      _cameraError = false;
      initCamera(selectedCameraIndex);
    }
  }

  Future<void> initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    // Await the previous session's teardown before opening a new one —
    // most camera HALs only allow one open session at a time, so firing
    // dispose() without awaiting let it race the new controller's
    // initialize() and could hang indefinitely (the "flip camera gets
    // stuck on loading" bug).
    await controller?.dispose();
    controller = null;
    if (mounted) setState(() {});

    controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    try {
      await controller!.initialize();
    } catch (_) {
      if (mounted) setState(() { controller = null; _cameraError = true; });
      return;
    }
    // Neither this screen nor the app manifest restricts device rotation,
    // so without this, recording while (even briefly) rotated captures the
    // video tagged/encoded in that orientation instead of upright. Best
    // effort: a lock failure here shouldn't take down an otherwise-working
    // camera.
    try {
      await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      selectedCameraIndex = cameraIndex;
      _cameraError = false;
    });
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2 || recording) return;
    final nextIndex = selectedCameraIndex == 0 ? 1 : 0;
    await initCamera(nextIndex);
  }

  Future<void> recordVideo() async {
    if (controller == null || !controller!.value.isInitialized) return;

    if (!recording) {
      await controller!.startVideoRecording();
      setState(() => recording = true);
    } else {
      videoFile = await controller!.stopVideoRecording();
      setState(() => recording = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 52),
              const SizedBox(height: 12),
              const Text('Camera unavailable',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() => _cameraError = false);
                  initCamera(selectedCameraIndex);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Record Challenge Video"),
        actions: [
          IconButton(
            onPressed: switchCamera,
            icon: const Icon(Icons.flip_camera_android),
          ),
        ],
      ),
      body: Column(
        children: [
          // CameraPreview has no intrinsic size — inside an Expanded slot it
          // simply stretches to fill the box, distorting the image whenever
          // the sensor's aspect ratio (previewSize, always reported in
          // landscape orientation regardless of device rotation) doesn't
          // match the available space. FittedBox+SizedBox at the true
          // (width/height swapped for portrait) preview size scale-crops
          // instead of stretching.
          Expanded(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize!.height,
                height: controller!.value.previewSize!.width,
                child: CameraPreview(controller!),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: recordVideo,
                    child: Text(recording ? "Stop Recording" : "Record Video"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: videoFile == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BrandPreviewScreen(
                                  videoPath:        videoFile!.path,
                                  challengeTitle:   widget.challengeTitle,
                                  description:      widget.description,
                                  instructions:     widget.instructions,
                                  difficulty:       widget.difficulty,
                                  categoryId:       widget.categoryId,
                                  instructionSteps: widget.instructionSteps,
                                ),
                              ),
                            );
                          },
                    child: const Text("Preview Video"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        videoFile = null;
                        recording = false;
                      });
                    },
                    child: const Text("Record Again"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
