import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../core/globals.dart';
import '../../video/screens/preview_screen.dart';

class CameraScreen extends StatefulWidget {
  final String challengeTitle;
  final String challengeId;

  const CameraScreen({
    super.key,
    required this.challengeTitle,
    required this.challengeId,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
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

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Record"),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: recordVideo,
                    child: Text(recording ? "Stop" : "Record"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: videoFile == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PreviewScreen(
                                  videoPath: videoFile!.path,
                                  challengeTitle: widget.challengeTitle,
                                  challengeId: widget.challengeId,
                                ),
                              ),
                            );
                          },
                    child: const Text("Preview"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
