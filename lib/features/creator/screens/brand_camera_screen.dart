import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../core/globals.dart';
import 'brand_preview_screen.dart';

class BrandCameraScreen extends StatefulWidget {
  final String       challengeTitle;
  final String       description;
  final String       instructions;
  final String       difficulty;
  final List<String> instructionSteps;
  final List<String> scoringChecklist;

  const BrandCameraScreen({
    super.key,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
    this.difficulty       = 'Medium',
    this.instructionSteps = const [],
    this.scoringChecklist = const [],
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

    controller?.dispose();

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
                  style: TextStyle(color: Colors.white54)),
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
          Expanded(child: CameraPreview(controller!)),
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
                                  instructionSteps: widget.instructionSteps,
                                  scoringChecklist: widget.scoringChecklist,
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
