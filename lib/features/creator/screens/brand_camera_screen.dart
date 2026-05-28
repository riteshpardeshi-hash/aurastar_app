import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../core/globals.dart';
import 'brand_preview_screen.dart';

class BrandCameraScreen extends StatefulWidget {
  final String challengeTitle;
  final String description;
  final String instructions;

  const BrandCameraScreen({
    super.key,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
  });

  @override
  State<BrandCameraScreen> createState() => _BrandCameraScreenState();
}

class _BrandCameraScreenState extends State<BrandCameraScreen> {
  CameraController? controller;
  bool recording = false;
  XFile? videoFile;
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    initCamera(selectedCameraIndex);
  }

  Future<void> initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    controller?.dispose();

    controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    await controller!.initialize();

    if (mounted) {
      setState(() {
        selectedCameraIndex = cameraIndex;
      });
    }
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
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                                  videoPath: videoFile!.path,
                                  challengeTitle: widget.challengeTitle,
                                  description: widget.description,
                                  instructions: widget.instructions,
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
